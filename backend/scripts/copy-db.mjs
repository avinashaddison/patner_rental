// One-off: copy ALL data from a source Postgres (Neon) into a dest Postgres
// (Supabase). Assumes the dest schema already exists (run `prisma migrate
// deploy` against the dest first). FK order is bypassed with
// session_replication_role=replica, so tables can be copied in any order.
//
// Usage:
//   SRC_URL="postgres://…neon…" DST_URL="postgres://…supabase DIRECT (5432)…" \
//     node scripts/copy-db.mjs
//
// DST_URL MUST be the DIRECT connection (port 5432), not the PgBouncer pooler —
// session-level SETs don't survive transaction-mode pooling.
import pg from 'pg';

const { Client } = pg;
const SRC = process.env.SRC_URL;
const DST = process.env.DST_URL;
const BATCH = 400;

if (!SRC || !DST) {
  console.error('SRC_URL and DST_URL env vars are required');
  process.exit(1);
}

const src = new Client({ connectionString: SRC, ssl: { rejectUnauthorized: false } });
const dst = new Client({ connectionString: DST, ssl: { rejectUnauthorized: false } });

async function main() {
  await src.connect();
  await dst.connect();

  const { rows: tbls } = await dst.query(`
    SELECT table_name FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
      AND table_name <> '_prisma_migrations'
    ORDER BY table_name
  `);
  const tables = tbls.map((r) => r.table_name);
  console.log(`dest has ${tables.length} tables to fill`);

  // Bypass FK/trigger checks for the load (needs the postgres role; Supabase ok).
  await dst.query(`SET session_replication_role = 'replica'`);

  let grandTotal = 0;
  const summary = [];
  for (const t of tables) {
    const { rows: cols } = await dst.query(
      `SELECT column_name, data_type FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = $1
       ORDER BY ordinal_position`,
      [t],
    );
    const colNames = cols.map((c) => c.column_name);
    const jsonCols = new Set(
      cols.filter((c) => c.data_type === 'jsonb' || c.data_type === 'json')
        .map((c) => c.column_name),
    );

    let rows;
    try {
      ({ rows } = await src.query(`SELECT * FROM "${t}"`));
    } catch (e) {
      console.log(`  ${t}: SKIP (not in source: ${e.message})`);
      summary.push(`${t}=skip`);
      continue;
    }
    if (rows.length === 0) {
      summary.push(`${t}=0`);
      continue;
    }

    const colList = colNames.map((c) => `"${c}"`).join(',');
    for (let i = 0; i < rows.length; i += BATCH) {
      const chunk = rows.slice(i, i + BATCH);
      const values = [];
      const tuples = chunk.map((row, ri) => {
        const ph = colNames.map((c, ci) => {
          let v = row[c];
          if (v !== null && v !== undefined && jsonCols.has(c)) v = JSON.stringify(v);
          values.push(v ?? null);
          return `$${ri * colNames.length + ci + 1}`;
        });
        return `(${ph.join(',')})`;
      });
      await dst.query(
        `INSERT INTO "${t}" (${colList}) VALUES ${tuples.join(',')} ON CONFLICT DO NOTHING`,
        values,
      );
    }
    console.log(`  ${t}: ${rows.length}`);
    grandTotal += rows.length;
    summary.push(`${t}=${rows.length}`);
  }

  await dst.query(`SET session_replication_role = 'origin'`);
  console.log(`\nTOTAL ROWS COPIED: ${grandTotal}`);
  console.log('PER-TABLE:', summary.join(' '));

  await src.end();
  await dst.end();
}

main().catch(async (e) => {
  console.error('COPY FAILED:', e.message);
  try { await src.end(); } catch {}
  try { await dst.end(); } catch {}
  process.exit(1);
});
