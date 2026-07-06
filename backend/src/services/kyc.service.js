// KYC business logic. Companions upload GOVERNMENT_ID + SELFIE; admins approve.
// A companion's profile only goes live when status=APPROVED AND both KYC docs APPROVED.
//
// The "companion-related KYC state" is derived from the kyc_documents rows for the
// user (there is no separate column): overall status is the rollup of the two
// required document types.
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';
import { notify } from './notification.service.js';

const REQUIRED_DOC_TYPES = ['GOVERNMENT_ID', 'SELFIE'];

function docToDto(d) {
  return {
    id: d.id,
    docType: d.docType,
    documentUrl: d.documentUrl,
    documentNumber: d.documentNumber || null,
    status: d.status,
    reviewNotes: d.reviewNotes || null,
    reviewedAt: d.reviewedAt || null,
    createdAt: d.createdAt,
  };
}

/**
 * Roll up the overall KYC status from the latest doc per required type.
 * - REJECTED if any required doc is REJECTED
 * - APPROVED only if both required docs are APPROVED
 * - SUBMITTED if both required docs are present and none rejected (under review)
 * - PENDING otherwise (incomplete)
 */
export function rollupStatus(docsByType) {
  const gov = docsByType.GOVERNMENT_ID;
  const selfie = docsByType.SELFIE;

  if (gov?.status === 'REJECTED' || selfie?.status === 'REJECTED') return 'REJECTED';
  if (gov?.status === 'APPROVED' && selfie?.status === 'APPROVED') return 'APPROVED';
  if (gov && selfie) return 'SUBMITTED';
  return 'PENDING';
}

/** Latest doc per required type for a user. */
async function latestDocsByType(userId, client = prisma) {
  const docs = await client.kycDocument.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
  });
  const byType = {};
  for (const d of docs) {
    if (!byType[d.docType]) byType[d.docType] = d; // first = newest due to desc order
  }
  return { byType, all: docs };
}

/**
 * Submit (or re-submit) a KYC document. Creates a new PENDING kyc_documents row.
 * Re-submitting a type supersedes the previous one (we keep history; rollup uses latest).
 * @param {object} user  authenticated COMPANION user
 * @param {{documentType, documentUrl, documentNumber?}} body
 */
export async function submitKyc(user, body) {
  // Companion profile should exist (the route guards role=COMPANION).
  const companion = await prisma.companion.findUnique({ where: { userId: user.id }, select: { id: true } });
  if (!companion) throw ApiError.notFound('Onboard your companion profile before submitting KYC.');

  const doc = await prisma.kycDocument.create({
    data: {
      userId: user.id,
      docType: body.documentType,
      documentUrl: body.documentUrl,
      documentNumber: body.documentNumber ?? null,
      status: 'PENDING',
    },
  });

  const { byType } = await latestDocsByType(user.id);
  const overall = rollupStatus(byType);
  const submitted = REQUIRED_DOC_TYPES.filter((t) => byType[t]);

  // Notify the companion that the document is received / under review.
  await notify(user.id, {
    type: 'KYC',
    title: 'KYC document received',
    body:
      submitted.length === REQUIRED_DOC_TYPES.length
        ? 'Both documents submitted. Verification is in progress.'
        : `${body.documentType.replace('_', ' ')} received. Submit the remaining document to complete KYC.`,
    data: { overall, docType: body.documentType },
  });

  return {
    document: docToDto(doc),
    overall,
    submittedTypes: submitted,
    missingTypes: REQUIRED_DOC_TYPES.filter((t) => !byType[t]),
  };
}

/**
 * Overall KYC status + the docs.
 * @param {object} user
 */
export async function getStatus(user) {
  const { byType, all } = await latestDocsByType(user.id);
  const overall = rollupStatus(byType);
  return {
    overall,
    isVerified: overall === 'APPROVED',
    requiredTypes: REQUIRED_DOC_TYPES,
    submittedTypes: REQUIRED_DOC_TYPES.filter((t) => byType[t]),
    missingTypes: REQUIRED_DOC_TYPES.filter((t) => !byType[t]),
    documents: all.map(docToDto),
  };
}

export default { submitKyc, getStatus, rollupStatus };
