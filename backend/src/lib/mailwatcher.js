// Bank credit-alert mail watcher — the confirmation engine for self-hosted
// UPI QR payments (payments.service 'upiqr').
//
// Connects to the mailbox over IMAP (Gmail + app password), keeps INBOX open
// with IDLE so new mail is pushed in near-realtime, parses credit alerts from
// the bank sender (default alerts@axis.bank.in), extracts amount + UTR, and
// hands them to payments.service.handleBankCredit for matching + capture.
//
// Axis alert shapes this parser handles (see sample email):
//   Subject: "INR 2000.00 was credited to your A/c."
//   Body:    "Amount Credited: INR 2,000.00"
//            "Transaction Info: UPI/P2A/650321330050/SODHA DIL/KKBK/UPI"
import { ImapFlow } from 'imapflow';
import { simpleParser } from 'mailparser';
import { config } from '../config/index.js';
import { logger } from './logger.js';
import { handleBankCredit, expireStaleQrOrders } from '../services/payments.service.js';

let client = null;
let stopped = false;
let reconnectDelay = 5_000;
let expiryTimer = null;

/** A bare "INR 2,000.00" number → 2000. */
function parseInrNumber(text) {
  const m = /INR\s*([\d,]+(?:\.\d{1,2})?)/i.exec(text);
  if (!m) return null;
  const n = Number(m[1].replace(/,/g, ''));
  return Number.isFinite(n) ? n : null;
}

/**
 * The CREDITED amount. Anchor to the "Amount Credited" label first so we never
 * pick up the "Available Balance" line; only fall back to a generic scan of the
 * subject (which for these alerts is itself the credited amount).
 */
function parseCreditAmount(subject, body) {
  const labelled =
    /Amount\s*Credited[^\d₹]*(?:INR|₹)\s*([\d,]+(?:\.\d{1,2})?)/i.exec(body) ||
    /(?:credited\s*(?:with|by|:)?)[^\d₹]*(?:INR|₹)\s*([\d,]+(?:\.\d{1,2})?)/i.exec(body);
  if (labelled) {
    const n = Number(labelled[1].replace(/,/g, ''));
    if (Number.isFinite(n)) return n;
  }
  // Subject on Axis credit alerts is "INR 2000.00 was credited to your A/c."
  return parseInrNumber(subject);
}

/** Parse the UTR out of "UPI/P2A/650321330050/NAME/BANK/..." (9–18 digits). */
function parseUtr(text) {
  const upi = /UPI\/[A-Z0-9]{0,6}\/(\d{9,18})\//i.exec(text);
  if (upi) return upi[1];
  // Fallback: a labelled UTR / reference number.
  const labelled = /(?:UTR|RRN|reference(?:\s*no\.?)?)[:\s]*(\d{9,18})/i.exec(text);
  return labelled ? labelled[1] : null;
}

function looksLikeCreditAlert(subject, body) {
  const s = `${subject}\n${body}`;
  // Must be a genuine credit-to-our-account phrase, and must NOT be a debit /
  // failure / reversal notice that merely mentions the word "credited".
  const positive =
    /\bcredited to your\b/i.test(s) ||
    /\bhas been credited\b/i.test(s) ||
    /\bwas credited\b/i.test(s) ||
    /Amount\s*Credited/i.test(s);
  const negative = /\bdebited\b/i.test(s) || /\bnot credited\b/i.test(s) || /\bfailed\b/i.test(s) || /\breversed\b/i.test(s);
  return positive && !negative && /(?:INR|₹)/i.test(s);
}

/** Process one raw RFC822 message. */
async function processMessage(source) {
  let parsed;
  try {
    parsed = await simpleParser(source);
  } catch (err) {
    logger.warn(`[mailwatch] unparseable message: ${err.message}`);
    return;
  }

  const from = (parsed.from?.value?.[0]?.address || '').toLowerCase();
  if (from !== config.mailwatch.alertFrom.toLowerCase()) return;

  const subject = parsed.subject || '';
  const body = `${parsed.text || ''}\n${parsed.html || ''}`;
  if (!looksLikeCreditAlert(subject, body)) return;

  const amount = parseCreditAmount(subject, body);
  const utr = parseUtr(body) ?? parseUtr(subject);

  if (!amount || !utr) {
    logger.warn(
      `[mailwatch] credit alert but couldn't parse (amount=${amount}, utr=${utr}) subject="${subject}"`,
    );
    return;
  }

  logger.info(`[mailwatch] credit alert: INR ${amount} UTR ${utr}`);
  try {
    await handleBankCredit({ amount, utr, receivedAt: parsed.date?.toISOString?.() });
  } catch (err) {
    logger.error(`[mailwatch] handleBankCredit failed for UTR ${utr}: ${err.message}`);
  }
}

// Serialize sweeps: the IDLE 'exists' handler and the post-connect catch-up can
// both fire. Overlapping sweeps would fetch + process the same UID twice and
// race the capture. If a sweep is asked for while one runs, we re-run once after.
let sweepInFlight = null;
let sweepQueued = false;

function sweepUnseen() {
  if (sweepInFlight) {
    sweepQueued = true;
    return sweepInFlight;
  }
  sweepInFlight = (async () => {
    try {
      await doSweep();
    } finally {
      sweepInFlight = null;
      if (sweepQueued) {
        sweepQueued = false;
        // Chain another pass for mail that arrived mid-sweep.
        sweepUnseen().catch((err) => logger.warn(`[mailwatch] sweep failed: ${err.message}`));
      }
    }
  })();
  return sweepInFlight;
}

/** Fetch + process any unseen mail from the alert sender, marking it seen. */
async function doSweep() {
  const uids = await client.search(
    { seen: false, from: config.mailwatch.alertFrom },
    { uid: true },
  );
  if (!uids || uids.length === 0) return;

  for (const uid of uids) {
    try {
      // Claim the message first (mark seen) so a racing connection won't also
      // process it, then handle it. A crash after this leaves it seen but
      // unprocessed — acceptable vs. double-capture.
      await client.messageFlagsAdd(String(uid), ['\\Seen'], { uid: true });
      const msg = await client.fetchOne(String(uid), { source: true }, { uid: true });
      if (msg?.source) await processMessage(msg.source);
    } catch (err) {
      logger.warn(`[mailwatch] failed processing uid ${uid}: ${err.message}`);
    }
  }
}

async function runLoop() {
  client = new ImapFlow({
    host: config.mailwatch.host,
    port: config.mailwatch.port,
    secure: true,
    auth: { user: config.mailwatch.user, pass: config.mailwatch.pass },
    logger: false,
  });

  client.on('error', (err) => logger.warn(`[mailwatch] imap error: ${err.message}`));

  await client.connect();
  await client.mailboxOpen('INBOX');
  logger.info(
    `[mailwatch] watching ${config.mailwatch.user} INBOX for ${config.mailwatch.alertFrom}`,
  );
  reconnectDelay = 5_000;

  // Catch up on anything that arrived while we were down.
  await sweepUnseen();

  // New-mail push: 'exists' fires when the message count changes (IDLE).
  client.on('exists', () => {
    sweepUnseen().catch((err) => logger.warn(`[mailwatch] sweep failed: ${err.message}`));
  });

  // Keep the connection alive; resolves when the connection closes.
  await client.idle();
}

/**
 * Start the watcher (no-op unless both mail credentials and the UPI VPA are
 * configured). Reconnects forever with capped backoff.
 */
export function startMailWatcher() {
  // Only mail credentials gate the watcher — the receiving VPA itself is
  // admin-controlled at runtime (settings `upi_vpa`, admin panel → Settings).
  if (!config.mailwatch.enabled) {
    logger.info('[mailwatch] disabled (set MAIL_IMAP_USER and MAIL_IMAP_PASS to enable)');
    return;
  }

  stopped = false;

  // Sweep expired QR orders every minute so paise tags recycle promptly.
  expiryTimer = setInterval(() => {
    expireStaleQrOrders().catch((err) =>
      logger.warn(`[mailwatch] expiry sweep failed: ${err.message}`),
    );
  }, 60_000);
  expiryTimer.unref?.();

  (async function loop() {
    while (!stopped) {
      try {
        await runLoop();
        logger.warn('[mailwatch] connection closed');
      } catch (err) {
        logger.warn(`[mailwatch] ${err.message}`);
      }
      try {
        await client?.logout?.();
      } catch {
        /* already gone */
      }
      if (stopped) break;
      await new Promise((r) => setTimeout(r, reconnectDelay));
      reconnectDelay = Math.min(reconnectDelay * 2, 120_000);
      logger.info('[mailwatch] reconnecting…');
    }
  })();
}

export async function stopMailWatcher() {
  stopped = true;
  if (expiryTimer) clearInterval(expiryTimer);
  try {
    await client?.logout?.();
  } catch {
    /* ignore */
  }
}

export default { startMailWatcher, stopMailWatcher };
