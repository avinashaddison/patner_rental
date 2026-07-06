// Admin business logic: auth, dashboards/analytics, user + companion moderation,
// KYC review, booking moderation + refunds, payments ledger, payout processing,
// reports, support, SOS, and runtime settings. Money math goes through ledger.service;
// settings through settings.service; user-facing alerts through notification.service.
import pkg from '@prisma/client';
import bcrypt from 'bcryptjs';
import dayjs from 'dayjs';
import { prisma } from '../lib/prisma.js';
import { signAdminToken } from '../lib/jwt.js';
import { logger } from '../lib/logger.js';
import { refundPayment } from '../lib/razorpay.js';
import { ApiError } from '../utils/apiResponse.js';
import { round2, refundToCustomer } from './ledger.service.js';
import { getSetting, setSetting } from './settings.service.js';
import { notify } from './notification.service.js';
import { isKycApproved } from './companions.service.js';
import { emitToUser } from '../lib/socket.js';
import { invalidateUserCache } from '../middleware/auth.js';
import { uploadImageBuffer } from '../lib/cloudinary.js';

const { Prisma } = pkg;
const D = (v) => new Prisma.Decimal(v ?? 0);

// ---------------------------------------------------------------------------
// Serializers — present DB rows as the API/JSON shape (Decimals -> numbers).
// ---------------------------------------------------------------------------

function num(v) {
  if (v == null) return v;
  return Number(D(v).toFixed(2));
}

function computeAge(dateOfBirth) {
  if (!dateOfBirth) return null;
  const age = dayjs().diff(dayjs(dateOfBirth), 'year');
  return Number.isFinite(age) ? age : null;
}

function serializeUser(user) {
  if (!user) return null;
  const { companion, wallet, _count, ...rest } = user;
  return {
    ...rest,
    age: computeAge(user.dateOfBirth),
    isCompanion: user.role === 'COMPANION',
    companion: companion ? serializeCompanionInline(companion) : undefined,
    wallet: wallet ? serializeWallet(wallet) : undefined,
    counts: _count || undefined,
  };
}

function serializeWallet(wallet) {
  if (!wallet) return null;
  return {
    ...wallet,
    balance: num(wallet.balance),
    pendingBalance: num(wallet.pendingBalance),
    totalEarned: num(wallet.totalEarned),
    totalWithdrawn: num(wallet.totalWithdrawn),
  };
}

function serializeCompanionInline(companion) {
  return {
    ...companion,
    hourlyRate: num(companion.hourlyRate),
    totalEarnings: num(companion.totalEarnings),
  };
}

function serializeCompanion(companion) {
  if (!companion) return null;
  const { user, photos, categories, availability, _count, ...rest } = companion;
  return {
    ...rest,
    hourlyRate: num(companion.hourlyRate),
    totalEarnings: num(companion.totalEarnings),
    name: user?.fullName ?? null,
    age: computeAge(user?.dateOfBirth),
    user: user ? serializeUser(user) : undefined,
    photos: photos || undefined,
    categories: categories ? categories.map((c) => c.category) : undefined,
    availability: availability || undefined,
    counts: _count || undefined,
  };
}

function serializeBooking(booking) {
  if (!booking) return null;
  const { customer, companion, category, payment, statusHistory, ...rest } = booking;
  return {
    ...rest,
    hourlyRate: num(booking.hourlyRate),
    totalAmount: num(booking.totalAmount),
    commissionAmount: num(booking.commissionAmount),
    companionPayout: num(booking.companionPayout),
    customer: customer ? serializeUser(customer) : undefined,
    companion: companion ? serializeCompanion(companion) : undefined,
    category: category || undefined,
    payment: payment ? serializePayment(payment) : undefined,
    statusHistory: statusHistory || undefined,
  };
}

function serializePayment(payment) {
  if (!payment) return null;
  const { booking, customer, ...rest } = payment;
  return {
    ...rest,
    amount: num(payment.amount),
    booking: booking ? serializeBookingLite(booking) : undefined,
    customer: customer ? serializeUserLite(customer) : undefined,
  };
}

function serializeBookingLite(booking) {
  return {
    id: booking.id,
    bookingCode: booking.bookingCode,
    activity: booking.activity,
    status: booking.status,
    totalAmount: num(booking.totalAmount),
    bookingDate: booking.bookingDate,
  };
}

function serializeUserLite(user) {
  if (!user) return null;
  return {
    id: user.id,
    fullName: user.fullName,
    mobileNumber: user.mobileNumber,
    email: user.email,
    role: user.role,
    profilePhotoUrl: user.profilePhotoUrl,
  };
}

function serializePayout(payout) {
  if (!payout) return null;
  const { user, ...rest } = payout;
  return {
    ...rest,
    amount: num(payout.amount),
    user: user ? serializeUserLite(user) : undefined,
  };
}

function serializeKycDoc(doc) {
  if (!doc) return null;
  const { user, ...rest } = doc;
  return { ...rest, user: user ? serializeUserLite(user) : undefined };
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

export async function login({ email, password }) {
  const admin = await prisma.adminUser.findUnique({ where: { email } });
  if (!admin || !admin.isActive) {
    throw ApiError.unauthorized('Invalid credentials');
  }
  const matches = await bcrypt.compare(password, admin.passwordHash);
  if (!matches) {
    throw ApiError.unauthorized('Invalid credentials');
  }

  const updated = await prisma.adminUser.update({
    where: { id: admin.id },
    data: { lastLoginAt: new Date() },
  });

  const token = signAdminToken(updated);
  return { token, admin: presentAdmin(updated) };
}

export function presentAdmin(admin) {
  if (!admin) return null;
  const { passwordHash: _passwordHash, ...rest } = admin;
  return rest;
}

export async function getAdminById(id) {
  const admin = await prisma.adminUser.findUnique({ where: { id } });
  if (!admin) throw ApiError.notFound('Admin not found');
  return presentAdmin(admin);
}

// ---------------------------------------------------------------------------
// Dashboard + analytics
// ---------------------------------------------------------------------------

export async function getDashboard() {
  const startOfToday = dayjs().startOf('day').toDate();
  const startOfWeek = dayjs().startOf('day').subtract(6, 'day').toDate();
  const startOfMonth = dayjs().startOf('month').toDate();

  const [
    revenueAgg,
    todayRevenueAgg,
    totalUsers,
    totalCustomers,
    totalCompanions,
    activeBookings,
    pendingCompanions,
    pendingKyc,
    openReports,
    activeSos,
    pendingPayouts,
    newToday,
    newThisWeek,
  ] = await Promise.all([
    prisma.payment.aggregate({ _sum: { amount: true }, where: { status: 'CAPTURED' } }),
    prisma.payment.aggregate({
      _sum: { amount: true },
      where: { status: 'CAPTURED', capturedAt: { gte: startOfToday } },
    }),
    prisma.user.count(),
    prisma.user.count({ where: { role: 'CUSTOMER' } }),
    prisma.user.count({ where: { role: 'COMPANION' } }),
    prisma.booking.count({ where: { status: { in: ['CONFIRMED', 'IN_PROGRESS'] } } }),
    prisma.companion.count({ where: { status: 'PENDING' } }),
    prisma.kycDocument.count({ where: { status: { in: ['PENDING', 'SUBMITTED'] } } }),
    prisma.report.count({ where: { status: { in: ['OPEN', 'REVIEWING'] } } }),
    prisma.sosAlert.count({ where: { status: 'ACTIVE' } }),
    prisma.payout.count({ where: { status: { in: ['REQUESTED', 'PROCESSING'] } } }),
    prisma.user.count({ where: { createdAt: { gte: startOfToday } } }),
    prisma.user.count({ where: { createdAt: { gte: startOfWeek } } }),
  ]);

  const totalRevenue = num(revenueAgg._sum.amount || 0);
  const commissionRate = Number(await getSetting('commission_rate', 20)) || 20;
  const platformEarnings = num(D(totalRevenue).mul(commissionRate).div(100));

  return {
    revenue: {
      total: totalRevenue,
      today: num(todayRevenueAgg._sum.amount || 0),
      platformEarnings,
      commissionRate,
    },
    totalUsers,
    totalCustomers,
    totalCompanions,
    activeBookings,
    newRegistrations: {
      today: newToday,
      week: newThisWeek,
    },
    pending: {
      companions: pendingCompanions,
      kyc: pendingKyc,
      reports: openReports,
      sos: activeSos,
      payouts: pendingPayouts,
    },
    period: {
      monthStart: startOfMonth,
      weekStart: startOfWeek,
    },
  };
}

const PERIOD_CONFIG = {
  daily: { unit: 'day', points: 30, fmt: 'YYYY-MM-DD' },
  weekly: { unit: 'week', points: 12, fmt: 'YYYY-[W]WW' },
  monthly: { unit: 'month', points: 12, fmt: 'YYYY-MM' },
  yearly: { unit: 'year', points: 5, fmt: 'YYYY' },
};

export async function getRevenueSeries(period = 'daily') {
  const cfg = PERIOD_CONFIG[period] || PERIOD_CONFIG.daily;
  const start = dayjs().startOf(cfg.unit).subtract(cfg.points - 1, cfg.unit);

  const payments = await prisma.payment.findMany({
    where: { status: 'CAPTURED', capturedAt: { gte: start.toDate() } },
    select: { amount: true, capturedAt: true },
    orderBy: { capturedAt: 'asc' },
  });

  const commissionRate = Number(await getSetting('commission_rate', 20)) || 20;

  // Build empty buckets so the series has a continuous time axis.
  const buckets = new Map();
  for (let i = 0; i < cfg.points; i += 1) {
    const d = start.add(i, cfg.unit);
    buckets.set(d.format(cfg.fmt), { period: d.format(cfg.fmt), revenue: D(0), bookings: 0 });
  }

  for (const p of payments) {
    if (!p.capturedAt) continue;
    const key = dayjs(p.capturedAt).startOf(cfg.unit).format(cfg.fmt);
    const bucket = buckets.get(key);
    if (!bucket) continue;
    bucket.revenue = bucket.revenue.plus(D(p.amount));
    bucket.bookings += 1;
  }

  const series = Array.from(buckets.values()).map((b) => ({
    period: b.period,
    revenue: num(b.revenue),
    platformEarnings: num(b.revenue.mul(commissionRate).div(100)),
    bookings: b.bookings,
  }));

  const totalRevenue = series.reduce((acc, b) => acc.plus(D(b.revenue)), D(0));

  return {
    period,
    points: cfg.points,
    from: start.toISOString(),
    series,
    totals: {
      revenue: num(totalRevenue),
      platformEarnings: num(totalRevenue.mul(commissionRate).div(100)),
      bookings: series.reduce((acc, b) => acc + b.bookings, 0),
    },
  };
}

export async function getAnalyticsOverview() {
  const [
    revenueAgg,
    totalUsers,
    totalCompanions,
    approvedCompanions,
    totalBookings,
    completedBookings,
    cancelledBookings,
    refundedAgg,
    totalReviews,
    ratingAgg,
    bookingsByStatus,
    payoutsAgg,
  ] = await Promise.all([
    prisma.payment.aggregate({ _sum: { amount: true }, _count: true, where: { status: 'CAPTURED' } }),
    prisma.user.count(),
    prisma.companion.count(),
    prisma.companion.count({ where: { status: 'APPROVED' } }),
    prisma.booking.count(),
    prisma.booking.count({ where: { status: 'COMPLETED' } }),
    prisma.booking.count({ where: { status: 'CANCELLED' } }),
    prisma.payment.aggregate({ _sum: { amount: true }, where: { status: 'REFUNDED' } }),
    prisma.review.count(),
    prisma.review.aggregate({ _avg: { overallRating: true } }),
    prisma.booking.groupBy({ by: ['status'], _count: { _all: true } }),
    prisma.payout.aggregate({ _sum: { amount: true }, where: { status: 'COMPLETED' } }),
  ]);

  const totalRevenue = num(revenueAgg._sum.amount || 0);
  const commissionRate = Number(await getSetting('commission_rate', 20)) || 20;
  const completionRate = totalBookings > 0 ? Number(((completedBookings / totalBookings) * 100).toFixed(1)) : 0;

  return {
    revenue: {
      total: totalRevenue,
      platformEarnings: num(D(totalRevenue).mul(commissionRate).div(100)),
      refunded: num(refundedAgg._sum.amount || 0),
      paidOut: num(payoutsAgg._sum.amount || 0),
      capturedPayments: revenueAgg._count || 0,
    },
    users: {
      total: totalUsers,
      companions: totalCompanions,
      approvedCompanions,
    },
    bookings: {
      total: totalBookings,
      completed: completedBookings,
      cancelled: cancelledBookings,
      completionRate,
      byStatus: bookingsByStatus.reduce((acc, row) => {
        acc[row.status] = row._count._all;
        return acc;
      }, {}),
    },
    reviews: {
      total: totalReviews,
      averageRating: ratingAgg._avg.overallRating
        ? Number(ratingAgg._avg.overallRating.toFixed(2))
        : 0,
    },
  };
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

export async function listUsers({ role, blocked, q }, { skip, take, orderBy }) {
  const where = {};
  if (role) where.role = role;
  if (typeof blocked === 'boolean') where.isBlocked = blocked;
  if (q) {
    where.OR = [
      { fullName: { contains: q, mode: 'insensitive' } },
      { mobileNumber: { contains: q, mode: 'insensitive' } },
      { email: { contains: q, mode: 'insensitive' } },
      { referralCode: { contains: q, mode: 'insensitive' } },
    ];
  }

  const [rows, total] = await Promise.all([
    prisma.user.findMany({
      where,
      skip,
      take,
      orderBy: orderBy || { createdAt: 'desc' },
      include: {
        companion: true,
        _count: { select: { bookingsAsCustomer: true, payouts: true } },
      },
    }),
    prisma.user.count({ where }),
  ]);

  return { items: rows.map(serializeUser), total };
}

export async function getUserDetail(id) {
  const user = await prisma.user.findUnique({
    where: { id },
    include: {
      companion: { include: { photos: true, categories: { include: { category: true } } } },
      wallet: true,
      kycDocuments: true,
      _count: {
        select: {
          bookingsAsCustomer: true,
          payouts: true,
          reviews: true,
          reportsReceived: true,
          sosAlerts: true,
        },
      },
    },
  });
  if (!user) throw ApiError.notFound('User not found');

  const recentBookings = await prisma.booking.findMany({
    where: { OR: [{ customerId: id }, { companion: { userId: id } }] },
    orderBy: { createdAt: 'desc' },
    take: 10,
    include: { companion: { include: { user: true } }, customer: true },
  });

  return {
    ...serializeUser(user),
    kycDocuments: (user.kycDocuments || []).map(serializeKycDoc),
    recentBookings: recentBookings.map(serializeBooking),
  };
}

export async function blockUser(id, reason, adminId) {
  const user = await prisma.user.findUnique({ where: { id } });
  if (!user) throw ApiError.notFound('User not found');
  if (user.role === 'ADMIN') throw ApiError.forbidden('Cannot block an admin account');

  const updated = await prisma.user.update({
    where: { id },
    data: { isBlocked: true, blockedReason: reason },
  });

  // If the user is a companion, suspend their public listing too.
  await prisma.companion.updateMany({
    where: { userId: id },
    data: { status: 'SUSPENDED', isOnline: false },
  });

  await notify(id, {
    type: 'SYSTEM',
    title: 'Account blocked',
    body: `Your account has been blocked. Reason: ${reason}`,
    data: { action: 'account_blocked' },
  }).catch((err) => logger.debug(`[admin] block notify skipped: ${err.message}`));

  invalidateUserCache(id); // kick the blocked user out of the auth cache now
  logger.info(`[admin] user ${id} blocked by admin ${adminId}`);
  return serializeUser(updated);
}

export async function unblockUser(id, adminId) {
  const user = await prisma.user.findUnique({ where: { id }, include: { companion: true } });
  if (!user) throw ApiError.notFound('User not found');

  const updated = await prisma.user.update({
    where: { id },
    data: { isBlocked: false, blockedReason: null },
  });

  // Restore a previously-suspended companion to APPROVED if they were approved before.
  if (user.companion && user.companion.status === 'SUSPENDED' && user.companion.approvedAt) {
    await prisma.companion.update({
      where: { id: user.companion.id },
      data: { status: 'APPROVED' },
    });
  }

  await notify(id, {
    type: 'SYSTEM',
    title: 'Account restored',
    body: 'Your account has been unblocked. Welcome back!',
    data: { action: 'account_unblocked' },
  }).catch((err) => logger.debug(`[admin] unblock notify skipped: ${err.message}`));

  invalidateUserCache(id);
  logger.info(`[admin] user ${id} unblocked by admin ${adminId}`);
  return serializeUser(updated);
}

// ---------------------------------------------------------------------------
// Companions
// ---------------------------------------------------------------------------

export async function listCompanions({ status, q }, { skip, take, orderBy }) {
  const where = {};
  if (status) where.status = status;
  if (q) {
    where.OR = [
      { user: { fullName: { contains: q, mode: 'insensitive' } } },
      { user: { mobileNumber: { contains: q, mode: 'insensitive' } } },
      { city: { contains: q, mode: 'insensitive' } },
    ];
  }

  const [rows, total] = await Promise.all([
    prisma.companion.findMany({
      where,
      skip,
      take,
      orderBy: orderBy || { createdAt: 'desc' },
      include: {
        user: true,
        photos: { orderBy: { sortOrder: 'asc' } },
        categories: { include: { category: true } },
        _count: { select: { bookings: true, reviews: true } },
      },
    }),
    prisma.companion.count({ where }),
  ]);

  return { items: rows.map(serializeCompanion), total };
}

async function loadCompanionOrThrow(id, include) {
  const companion = await prisma.companion.findUnique({ where: { id }, include });
  if (!companion) throw ApiError.notFound('Companion not found');
  return companion;
}

export async function getCompanionDetail(id) {
  const companion = await loadCompanionOrThrow(id, {
    user: { include: { kycDocuments: true, wallet: true } },
    photos: { orderBy: { sortOrder: 'asc' } },
    categories: { include: { category: true } },
    availability: { orderBy: [{ dayOfWeek: 'asc' }, { startTime: 'asc' }] },
    _count: { select: { bookings: true, reviews: true } },
  });

  const kyc = companion.user?.kycDocuments || [];
  const hasGovId = kyc.some((d) => d.docType === 'GOVERNMENT_ID' && d.status === 'APPROVED');
  const hasSelfie = kyc.some((d) => d.docType === 'SELFIE' && d.status === 'APPROVED');
  const kycApproved = hasGovId && hasSelfie;

  const serialized = serializeCompanion(companion);
  return {
    ...serialized,
    isVerified: companion.status === 'APPROVED' && kycApproved,
    kyc: {
      approved: kycApproved,
      documents: kyc.map(serializeKycDoc),
    },
  };
}

export async function approveCompanion(id, adminId) {
  const companion = await loadCompanionOrThrow(id);
  if (companion.status === 'APPROVED') {
    throw ApiError.conflict('Companion is already approved');
  }
  // Safety contract (d): a companion can only be APPROVED once both KYC
  // documents (government ID + selfie) are approved. This keeps "APPROVED"
  // from ever meaning "unverified", which the booking gate now also enforces.
  if (!(await isKycApproved(companion.userId))) {
    throw ApiError.badRequest(
      'Cannot approve: both KYC documents (government ID and selfie) must be approved first',
    );
  }
  const updated = await prisma.companion.update({
    where: { id },
    data: { status: 'APPROVED', approvedAt: new Date(), rejectedReason: null },
  });

  await notify(companion.userId, {
    type: 'KYC',
    title: 'Profile approved',
    body: 'Congratulations! Your companion profile is now live.',
    data: { action: 'companion_approved', companionId: id },
  }).catch((err) => logger.debug(`[admin] approve notify skipped: ${err.message}`));

  logger.info(`[admin] companion ${id} approved by admin ${adminId}`);
  return serializeCompanion({ ...updated, user: companion.user });
}

export async function rejectCompanion(id, reason, adminId) {
  const companion = await loadCompanionOrThrow(id);
  const updated = await prisma.companion.update({
    where: { id },
    data: { status: 'REJECTED', rejectedReason: reason, isOnline: false, isFeatured: false },
  });

  await notify(companion.userId, {
    type: 'KYC',
    title: 'Profile not approved',
    body: `Your companion profile was not approved. Reason: ${reason}`,
    data: { action: 'companion_rejected', companionId: id },
  }).catch((err) => logger.debug(`[admin] reject notify skipped: ${err.message}`));

  logger.info(`[admin] companion ${id} rejected by admin ${adminId}`);
  return serializeCompanion(updated);
}

export async function suspendCompanion(id, reason, adminId) {
  const companion = await loadCompanionOrThrow(id);
  const updated = await prisma.companion.update({
    where: { id },
    data: { status: 'SUSPENDED', rejectedReason: reason, isOnline: false, isFeatured: false },
  });

  await notify(companion.userId, {
    type: 'SYSTEM',
    title: 'Profile suspended',
    body: `Your companion profile has been suspended. Reason: ${reason}`,
    data: { action: 'companion_suspended', companionId: id },
  }).catch((err) => logger.debug(`[admin] suspend notify skipped: ${err.message}`));

  logger.info(`[admin] companion ${id} suspended by admin ${adminId}`);
  return serializeCompanion(updated);
}

export async function featureCompanion(id, isFeatured, adminId) {
  const companion = await loadCompanionOrThrow(id);
  if (isFeatured && companion.status !== 'APPROVED') {
    throw ApiError.conflict('Only approved companions can be featured');
  }
  const updated = await prisma.companion.update({
    where: { id },
    data: { isFeatured },
  });
  logger.info(`[admin] companion ${id} featured=${isFeatured} by admin ${adminId}`);
  return serializeCompanion(updated);
}

/**
 * Admin manually adds a KYC document for a companion (e.g. onboarded offline).
 * Uploads the image to Cloudinary, records it as an APPROVED, admin-verified
 * document, and auto-approves the companion if both docs are now approved and
 * they were still PENDING.
 * @param {string} companionId
 * @param {{docType:'GOVERNMENT_ID'|'SELFIE', documentNumber?:string, buffer:Buffer}} input
 */
export async function addCompanionKyc(companionId, { docType, documentNumber, buffer }, adminId) {
  const companion = await loadCompanionOrThrow(companionId);
  const userId = companion.userId;

  const documentUrl = await uploadImageBuffer({
    buffer,
    folder: 'companion-ranchi/kyc',
    publicId: `kyc-${userId}-${docType.toLowerCase()}-${Date.now()}`,
  });

  const doc = await prisma.kycDocument.create({
    data: {
      userId,
      docType,
      documentUrl,
      documentNumber: documentNumber || null,
      status: 'APPROVED',
      reviewedById: adminId,
      reviewedAt: new Date(),
      reviewNotes: 'Added and verified by admin',
    },
  });

  // If both required docs are now approved and the companion is still PENDING,
  // this promotes them to APPROVED automatically.
  await maybeAutoApproveCompanion(userId);

  logger.info(`[admin] KYC ${docType} added for companion ${companionId} by admin ${adminId}`);
  return serializeKycDoc(doc);
}

// ---------------------------------------------------------------------------
// KYC
// ---------------------------------------------------------------------------

export async function listKyc({ status }, { skip, take, orderBy }) {
  const where = {};
  if (status) where.status = status;
  else where.status = { in: ['PENDING', 'SUBMITTED'] };

  const [rows, total] = await Promise.all([
    prisma.kycDocument.findMany({
      where,
      skip,
      take,
      orderBy: orderBy || { createdAt: 'asc' },
      include: { user: true },
    }),
    prisma.kycDocument.count({ where }),
  ]);

  return { items: rows.map(serializeKycDoc), total };
}

async function maybeAutoApproveCompanion(userId) {
  // A companion becomes verifiable when BOTH GOVERNMENT_ID and SELFIE are APPROVED.
  const docs = await prisma.kycDocument.findMany({ where: { userId } });
  const hasGovId = docs.some((d) => d.docType === 'GOVERNMENT_ID' && d.status === 'APPROVED');
  const hasSelfie = docs.some((d) => d.docType === 'SELFIE' && d.status === 'APPROVED');
  if (!hasGovId || !hasSelfie) return;

  const companion = await prisma.companion.findUnique({ where: { userId } });
  if (companion && companion.status === 'PENDING') {
    await prisma.companion.update({
      where: { id: companion.id },
      data: { status: 'APPROVED', approvedAt: new Date(), rejectedReason: null },
    });
    await notify(userId, {
      type: 'KYC',
      title: 'Profile approved',
      body: 'Your KYC is verified and your companion profile is now live.',
      data: { action: 'companion_approved' },
    }).catch(() => {});
  }
}

export async function approveKyc(id, adminId) {
  const doc = await prisma.kycDocument.findUnique({ where: { id } });
  if (!doc) throw ApiError.notFound('KYC document not found');

  const updated = await prisma.kycDocument.update({
    where: { id },
    data: {
      status: 'APPROVED',
      reviewedById: adminId,
      reviewedAt: new Date(),
      reviewNotes: 'Approved',
    },
  });

  await notify(doc.userId, {
    type: 'KYC',
    title: 'Document verified',
    body: `Your ${doc.docType === 'GOVERNMENT_ID' ? 'government ID' : 'selfie'} has been verified.`,
    data: { action: 'kyc_approved', docType: doc.docType },
  }).catch((err) => logger.debug(`[admin] kyc approve notify skipped: ${err.message}`));

  await maybeAutoApproveCompanion(doc.userId);

  logger.info(`[admin] kyc ${id} approved by admin ${adminId}`);
  return serializeKycDoc(updated);
}

export async function rejectKyc(id, reason, adminId) {
  const doc = await prisma.kycDocument.findUnique({ where: { id } });
  if (!doc) throw ApiError.notFound('KYC document not found');

  const updated = await prisma.kycDocument.update({
    where: { id },
    data: {
      status: 'REJECTED',
      reviewedById: adminId,
      reviewedAt: new Date(),
      reviewNotes: reason,
    },
  });

  await notify(doc.userId, {
    type: 'KYC',
    title: 'Document rejected',
    body: `Your ${doc.docType === 'GOVERNMENT_ID' ? 'government ID' : 'selfie'} was rejected. Reason: ${reason}. Please re-submit.`,
    data: { action: 'kyc_rejected', docType: doc.docType },
  }).catch((err) => logger.debug(`[admin] kyc reject notify skipped: ${err.message}`));

  logger.info(`[admin] kyc ${id} rejected by admin ${adminId}`);
  return serializeKycDoc(updated);
}

// ---------------------------------------------------------------------------
// Bookings
// ---------------------------------------------------------------------------

export async function listBookings({ status, q }, { skip, take, orderBy }) {
  const where = {};
  if (status) where.status = status;
  if (q) {
    where.OR = [
      { bookingCode: { contains: q, mode: 'insensitive' } },
      { activity: { contains: q, mode: 'insensitive' } },
      { customer: { fullName: { contains: q, mode: 'insensitive' } } },
      { companion: { user: { fullName: { contains: q, mode: 'insensitive' } } } },
    ];
  }

  const [rows, total] = await Promise.all([
    prisma.booking.findMany({
      where,
      skip,
      take,
      orderBy: orderBy || { createdAt: 'desc' },
      include: {
        customer: true,
        companion: { include: { user: true } },
        category: true,
        payment: true,
      },
    }),
    prisma.booking.count({ where }),
  ]);

  return { items: rows.map(serializeBooking), total };
}

export async function getBookingDetail(id) {
  const booking = await prisma.booking.findUnique({
    where: { id },
    include: {
      customer: true,
      companion: { include: { user: true } },
      category: true,
      payment: true,
      review: true,
      statusHistory: { orderBy: { createdAt: 'asc' } },
    },
  });
  if (!booking) throw ApiError.notFound('Booking not found');
  const serialized = serializeBooking(booking);
  serialized.review = booking.review || null;
  return serialized;
}

// ---- Posts (moderation) ---------------------------------------------------

const postModerationInclude = {
  companion: { include: { user: { select: { id: true, fullName: true, mobileNumber: true } } } },
  _count: { select: { likes: true, comments: true } },
};

function serializePostModeration(p) {
  if (!p) return null;
  const { companion, _count, ...rest } = p;
  return {
    ...rest,
    // Prefer the authoritative aggregate counts (already fetched) so moderators
    // see true engagement even if a denormalized counter ever drifts.
    likeCount: _count?.likes ?? p.likeCount,
    commentCount: _count?.comments ?? p.commentCount,
    companion: companion
      ? {
          id: companion.id,
          status: companion.status,
          name: companion.user?.fullName || null,
          mobileNumber: companion.user?.mobileNumber || null,
          userId: companion.user?.id || null,
        }
      : null,
  };
}

export async function listPosts({ status, q }, { skip, take, orderBy }) {
  const where = {};
  if (status) where.status = status;
  if (q) {
    where.OR = [
      { caption: { contains: q, mode: 'insensitive' } },
      { companion: { user: { fullName: { contains: q, mode: 'insensitive' } } } },
    ];
  }
  const [rows, total] = await Promise.all([
    prisma.post.findMany({
      where,
      skip,
      take,
      orderBy: orderBy || { createdAt: 'desc' },
      include: postModerationInclude,
    }),
    prisma.post.count({ where }),
  ]);
  return { items: rows.map(serializePostModeration), total };
}

export async function getPostDetail(id) {
  const post = await prisma.post.findUnique({ where: { id }, include: postModerationInclude });
  if (!post) throw ApiError.notFound('Post not found');
  return serializePostModeration(post);
}

/** Hide (soft-remove) a post from public feeds; notifies the author. */
export async function removePost(id, adminId) {
  const post = await prisma.post.findUnique({
    where: { id },
    include: { companion: { select: { id: true, userId: true } } },
  });
  if (!post) throw ApiError.notFound('Post not found');
  if (post.status === 'REMOVED') return serializePostModeration(post);

  const updated = await prisma.$transaction(async (tx) => {
    const p = await tx.post.update({ where: { id }, data: { status: 'REMOVED' } });
    await tx.companion.update({
      where: { id: post.companionId },
      data: { postCount: { decrement: 1 } },
    });
    return p;
  });

  await notify(post.companion.userId, {
    type: 'SYSTEM',
    title: 'Post removed',
    body: 'One of your posts was removed by our moderation team for violating the content guidelines.',
    data: { kind: 'POST_REMOVED', postId: id },
  }).catch(() => {});

  logger.info(`[admin] post ${id} removed by admin ${adminId}`);
  return serializePostModeration({ ...updated, companion: undefined, _count: undefined });
}

/**
 * Admin "panel confirm": force a CONFIRMED booking to IN_PROGRESS without the
 * customer start code (override for when they can't locate it). Delegates to the
 * bookings status machine so history + notifications stay consistent.
 */
export async function startBooking(id, adminId) {
  const { startBookingByAdmin } = await import('./bookings.service.js');
  const data = await startBookingByAdmin(id, adminId);
  logger.info(`[admin] booking ${id} force-started by admin ${adminId}`);
  return data;
}

const CANCELLABLE = new Set(['PENDING', 'CONFIRMED', 'IN_PROGRESS']);

export async function cancelBooking(id, reason, adminId) {
  const booking = await prisma.booking.findUnique({ where: { id }, include: { payment: true } });
  if (!booking) throw ApiError.notFound('Booking not found');
  if (!CANCELLABLE.has(booking.status)) {
    throw ApiError.conflict(`Cannot cancel a booking in ${booking.status} state`);
  }

  const wasPaid = booking.payment && booking.payment.status === 'CAPTURED';
  const nextStatus = wasPaid ? 'REFUNDED' : 'CANCELLED';

  const updated = await prisma.$transaction(async (tx) => {
    const b = await tx.booking.update({
      where: { id },
      data: {
        status: nextStatus,
        cancelledById: adminId,
        cancellationReason: reason,
      },
    });
    await tx.bookingStatusHistory.create({
      data: {
        bookingId: id,
        status: nextStatus,
        changedById: adminId,
        note: `Admin cancellation: ${reason}`,
      },
    });
    return b;
  });

  // Refund money if the booking was paid (ledger + gateway, best-effort gateway).
  if (wasPaid) {
    await processRefund(booking, undefined);
  }

  await Promise.all([
    notify(booking.customerId, {
      type: 'BOOKING',
      title: 'Booking cancelled',
      body: `Your booking ${booking.bookingCode} was cancelled by support. Reason: ${reason}`,
      data: { action: 'booking_cancelled', bookingId: id, bookingCode: booking.bookingCode },
    }).catch(() => {}),
    notifyCompanionUser(booking.companionId, {
      type: 'BOOKING',
      title: 'Booking cancelled',
      body: `Booking ${booking.bookingCode} was cancelled by support.`,
      data: { action: 'booking_cancelled', bookingId: id },
    }),
  ]);

  logger.info(`[admin] booking ${id} cancelled (${nextStatus}) by admin ${adminId}`);
  return serializeBooking({ ...updated, payment: undefined });
}

async function notifyCompanionUser(companionId, payload) {
  try {
    const companion = await prisma.companion.findUnique({ where: { id: companionId } });
    if (companion) await notify(companion.userId, payload);
  } catch (err) {
    logger.debug(`[admin] companion notify skipped: ${err.message}`);
  }
}

/**
 * Refund a booking: credit the customer via the ledger and attempt a Razorpay
 * gateway refund when a captured payment exists. `amount` undefined = full refund.
 */
async function processRefund(booking, amount) {
  const full = await prisma.booking.findUnique({ where: { id: booking.id }, include: { payment: true } });
  const payment = full?.payment;

  // Ledger refund (wallet credit to customer + marks payment REFUNDED).
  // For a partial refund we credit only the requested amount; otherwise the full total.
  if (amount != null && Number(amount) > 0 && Number(amount) < Number(full.totalAmount)) {
    // Partial: credit just the requested amount as a REFUND transaction.
    const { creditWallet } = await import('./ledger.service.js');
    await creditWallet({
      userId: full.customerId,
      amount,
      type: 'REFUND',
      bookingId: full.id,
      description: `Partial refund for booking ${full.bookingCode}`,
      reference: full.bookingCode,
    });
    await prisma.payment.updateMany({ where: { bookingId: full.id }, data: { status: 'REFUNDED' } });
  } else {
    await refundToCustomer(full);
  }

  // Gateway refund (best-effort — never block the admin action on a gateway error).
  if (payment && payment.razorpayPaymentId && payment.status !== 'REFUNDED') {
    try {
      await refundPayment(payment.razorpayPaymentId, amount);
    } catch (err) {
      logger.error(`[admin] gateway refund failed for ${payment.razorpayPaymentId}: ${err.message}`);
    }
  }
}

export async function refundBooking(id, amount, adminId) {
  const booking = await prisma.booking.findUnique({ where: { id }, include: { payment: true } });
  if (!booking) throw ApiError.notFound('Booking not found');
  if (!booking.payment || booking.payment.status !== 'CAPTURED') {
    throw ApiError.conflict('Booking has no captured payment to refund');
  }
  if (amount != null && Number(amount) > Number(booking.totalAmount)) {
    throw ApiError.badRequest('Refund amount exceeds the booking total');
  }

  await processRefund(booking, amount);

  const updated = await prisma.$transaction(async (tx) => {
    const b = await tx.booking.update({
      where: { id },
      data: { status: 'REFUNDED', cancelledById: adminId, cancellationReason: 'Refunded by admin' },
    });
    await tx.bookingStatusHistory.create({
      data: {
        bookingId: id,
        status: 'REFUNDED',
        changedById: adminId,
        note: amount != null ? `Partial refund of ${amount} by admin` : 'Full refund by admin',
      },
    });
    return b;
  });

  await notify(booking.customerId, {
    type: 'PAYMENT',
    title: 'Refund issued',
    body: `A refund of ₹${amount != null ? Number(amount) : num(booking.totalAmount)} for booking ${booking.bookingCode} has been processed.`,
    data: { action: 'booking_refunded', bookingId: id, bookingCode: booking.bookingCode },
  }).catch((err) => logger.debug(`[admin] refund notify skipped: ${err.message}`));

  logger.info(`[admin] booking ${id} refunded by admin ${adminId}`);
  return serializeBooking(updated);
}

// ---------------------------------------------------------------------------
// Payments ledger
// ---------------------------------------------------------------------------

export async function listPayments({ status, q }, { skip, take, orderBy }) {
  const where = {};
  if (status) where.status = status;
  if (q) {
    where.OR = [
      { razorpayOrderId: { contains: q, mode: 'insensitive' } },
      { razorpayPaymentId: { contains: q, mode: 'insensitive' } },
      { booking: { bookingCode: { contains: q, mode: 'insensitive' } } },
    ];
  }

  const [rows, total, agg] = await Promise.all([
    prisma.payment.findMany({
      where,
      skip,
      take,
      orderBy: orderBy || { createdAt: 'desc' },
      include: { booking: true, customer: true },
    }),
    prisma.payment.count({ where }),
    prisma.payment.aggregate({ _sum: { amount: true }, where: { ...where, status: 'CAPTURED' } }),
  ]);

  return {
    items: rows.map(serializePayment),
    total,
    summary: { capturedTotal: num(agg._sum.amount || 0) },
  };
}

// ---------------------------------------------------------------------------
// Payouts
// ---------------------------------------------------------------------------

export async function listPayouts({ status }, { skip, take, orderBy }) {
  const where = {};
  if (status) where.status = status;

  const [rows, total] = await Promise.all([
    prisma.payout.findMany({
      where,
      skip,
      take,
      orderBy: orderBy || { createdAt: 'desc' },
      include: { user: true },
    }),
    prisma.payout.count({ where }),
  ]);

  return { items: rows.map(serializePayout), total };
}

/**
 * Process (approve) a payout: mark COMPLETED, debit the companion's wallet
 * balance, and bump wallet.totalWithdrawn. All inside one transaction so the
 * ledger stays consistent. Records a PAYOUT transaction.
 */
export async function processPayout(id, notes, adminId) {
  const payout = await prisma.payout.findUnique({ where: { id } });
  if (!payout) throw ApiError.notFound('Payout not found');
  if (!['REQUESTED', 'PROCESSING'].includes(payout.status)) {
    throw ApiError.conflict(`Payout already ${payout.status}`);
  }

  const updated = await prisma.$transaction(async (tx) => {
    const wallet = await tx.wallet.findUnique({ where: { userId: payout.userId } });
    if (!wallet) throw ApiError.conflict('Companion wallet not found');

    const amount = round2(payout.amount);
    if (D(wallet.balance).lt(amount)) {
      throw ApiError.conflict('Insufficient wallet balance for this payout');
    }

    const newBalance = round2(D(wallet.balance).minus(amount));
    const newWithdrawn = round2(D(wallet.totalWithdrawn).plus(amount));

    await tx.wallet.update({
      where: { id: wallet.id },
      data: { balance: newBalance, totalWithdrawn: newWithdrawn },
    });

    await tx.transaction.create({
      data: {
        walletId: wallet.id,
        userId: payout.userId,
        type: 'PAYOUT',
        amount: amount.negated(),
        balanceAfter: newBalance,
        status: 'COMPLETED',
        reference: payout.id,
        description: `Payout via ${payout.method}${notes ? ` — ${notes}` : ''}`,
      },
    });

    return tx.payout.update({
      where: { id },
      data: {
        status: 'COMPLETED',
        processedById: adminId,
        processedAt: new Date(),
        notes: notes || payout.notes,
      },
    });
  });

  await notify(payout.userId, {
    type: 'PAYMENT',
    title: 'Payout processed',
    body: `Your payout of ₹${num(payout.amount)} has been processed.`,
    data: { action: 'payout_completed', payoutId: id },
  }).catch((err) => logger.debug(`[admin] payout notify skipped: ${err.message}`));

  logger.info(`[admin] payout ${id} processed by admin ${adminId}`);
  return serializePayout(updated);
}

export async function rejectPayout(id, reason, adminId) {
  const payout = await prisma.payout.findUnique({ where: { id } });
  if (!payout) throw ApiError.notFound('Payout not found');
  if (!['REQUESTED', 'PROCESSING'].includes(payout.status)) {
    throw ApiError.conflict(`Payout already ${payout.status}`);
  }

  const updated = await prisma.payout.update({
    where: { id },
    data: {
      status: 'REJECTED',
      processedById: adminId,
      processedAt: new Date(),
      notes: reason,
    },
  });

  await notify(payout.userId, {
    type: 'PAYMENT',
    title: 'Payout rejected',
    body: `Your payout request of ₹${num(payout.amount)} was rejected. Reason: ${reason}`,
    data: { action: 'payout_rejected', payoutId: id },
  }).catch((err) => logger.debug(`[admin] payout reject notify skipped: ${err.message}`));

  logger.info(`[admin] payout ${id} rejected by admin ${adminId}`);
  return serializePayout(updated);
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

export async function listReports({ status }, { skip, take, orderBy }) {
  const where = {};
  if (status) where.status = status;

  const [rows, total] = await Promise.all([
    prisma.report.findMany({
      where,
      skip,
      take,
      orderBy: orderBy || { createdAt: 'desc' },
      include: {
        reporter: { select: { id: true, fullName: true, mobileNumber: true, role: true } },
        reportedUser: { select: { id: true, fullName: true, mobileNumber: true, role: true } },
      },
    }),
    prisma.report.count({ where }),
  ]);

  return { items: rows, total };
}

export async function resolveReport(id, { resolutionNotes, status }, adminId) {
  const report = await prisma.report.findUnique({ where: { id } });
  if (!report) throw ApiError.notFound('Report not found');

  const updated = await prisma.report.update({
    where: { id },
    data: {
      status,
      resolutionNotes,
      reviewedById: adminId,
      resolvedAt: new Date(),
    },
    include: {
      reporter: { select: { id: true, fullName: true } },
      reportedUser: { select: { id: true, fullName: true } },
    },
  });

  await notify(report.reporterId, {
    type: 'SYSTEM',
    title: 'Report reviewed',
    body: status === 'RESOLVED'
      ? 'Thank you. The report you filed has been reviewed and resolved.'
      : 'The report you filed has been reviewed and dismissed.',
    data: { action: 'report_resolved', reportId: id, status },
  }).catch((err) => logger.debug(`[admin] report notify skipped: ${err.message}`));

  logger.info(`[admin] report ${id} resolved (${status}) by admin ${adminId}`);
  return updated;
}

// ---------------------------------------------------------------------------
// Support tickets
// ---------------------------------------------------------------------------

export async function listTickets({ status }, { skip, take, orderBy }) {
  const where = {};
  if (status) where.status = status;

  const [rows, total] = await Promise.all([
    prisma.supportTicket.findMany({
      where,
      skip,
      take,
      orderBy: orderBy || { createdAt: 'desc' },
      include: {
        user: { select: { id: true, fullName: true, mobileNumber: true, email: true } },
        _count: { select: { messages: true } },
        // Latest message so the desk can flag threads awaiting an admin reply.
        messages: { orderBy: { createdAt: 'desc' }, take: 1, select: { senderId: true } },
      },
    }),
    prisma.supportTicket.count({ where }),
  ]);

  // `awaitingReply`: the last message came from the user (not staff) and the
  // ticket isn't closed — i.e. it needs an admin response. Drives the live badge.
  const items = rows.map(({ messages, ...t }) => ({
    ...t,
    awaitingReply:
      t.status !== 'CLOSED' &&
      messages.length > 0 &&
      messages[0].senderId === t.userId,
  }));

  return { items, total };
}

/** Count tickets awaiting an admin reply (last message from the user, not closed). */
export async function countAwaitingReply() {
  const rows = await prisma.supportTicket.findMany({
    where: { status: { in: ['OPEN', 'IN_PROGRESS'] } },
    select: {
      userId: true,
      messages: { orderBy: { createdAt: 'desc' }, take: 1, select: { senderId: true } },
    },
  });
  return rows.filter((t) => t.messages.length > 0 && t.messages[0].senderId === t.userId)
    .length;
}

export async function getTicketDetail(id) {
  const ticket = await prisma.supportTicket.findUnique({
    where: { id },
    include: {
      user: { select: { id: true, fullName: true, mobileNumber: true, email: true } },
      messages: { orderBy: { createdAt: 'asc' } },
    },
  });
  if (!ticket) throw ApiError.notFound('Ticket not found');
  return ticket;
}

// A ticket message's `senderId` is a FK to `users.id`, but admins live in the
// separate `admin_users` table. So staff replies are attributed to a single
// dedicated "Support" User account (find-or-create, cached). The replying
// admin is still tracked on the ticket via `assignedToId`.
const SUPPORT_USER_MOBILE = '0000000000';
let _supportUserId = null;
async function getSupportUserId() {
  if (_supportUserId) return _supportUserId;
  const user = await prisma.user.upsert({
    where: { mobileNumber: SUPPORT_USER_MOBILE },
    update: {},
    create: {
      mobileNumber: SUPPORT_USER_MOBILE,
      fullName: 'Companion Ranchi Support',
      role: 'ADMIN',
      isMobileVerified: true,
      referralCode: 'SUPPORTDESK',
    },
    select: { id: true },
  });
  _supportUserId = user.id;
  return user.id;
}

export async function replyToTicket(id, message, adminId) {
  const ticket = await prisma.supportTicket.findUnique({ where: { id } });
  if (!ticket) throw ApiError.notFound('Ticket not found');

  const supportUserId = await getSupportUserId();
  const created = await prisma.$transaction(async (tx) => {
    const msg = await tx.ticketMessage.create({
      data: { ticketId: id, senderId: supportUserId, message },
    });
    // Moving an OPEN ticket to IN_PROGRESS on first admin reply, and assign.
    await tx.supportTicket.update({
      where: { id },
      data: {
        status: ticket.status === 'OPEN' ? 'IN_PROGRESS' : ticket.status,
        assignedToId: ticket.assignedToId || adminId,
      },
    });
    return msg;
  });

  // Realtime push so the user sees the reply instantly in the live support chat.
  emitToUser(ticket.userId, 'support:message', {
    ticketId: id,
    message: {
      id: created.id,
      message: created.message,
      role: 'SUPPORT',
      isMine: false,
      createdAt: created.createdAt,
    },
  });

  await notify(ticket.userId, {
    type: 'SYSTEM',
    title: 'Support replied',
    body: `Support replied to your ticket "${ticket.subject}".`,
    data: { action: 'ticket_reply', ticketId: id },
  }).catch((err) => logger.debug(`[admin] ticket reply notify skipped: ${err.message}`));

  logger.info(`[admin] ticket ${id} replied by admin ${adminId}`);
  return created;
}

export async function updateTicketStatus(id, status, adminId) {
  const ticket = await prisma.supportTicket.findUnique({ where: { id } });
  if (!ticket) throw ApiError.notFound('Ticket not found');

  const isClosing = status === 'RESOLVED' || status === 'CLOSED';
  const updated = await prisma.supportTicket.update({
    where: { id },
    data: {
      status,
      resolvedAt: isClosing ? new Date() : null,
      assignedToId: ticket.assignedToId || adminId,
    },
  });

  await notify(ticket.userId, {
    type: 'SYSTEM',
    title: 'Ticket updated',
    body: `Your support ticket "${ticket.subject}" is now ${status.replace('_', ' ').toLowerCase()}.`,
    data: { action: 'ticket_status', ticketId: id, status },
  }).catch((err) => logger.debug(`[admin] ticket status notify skipped: ${err.message}`));

  logger.info(`[admin] ticket ${id} -> ${status} by admin ${adminId}`);
  return updated;
}

// ---------------------------------------------------------------------------
// SOS
// ---------------------------------------------------------------------------

export async function listSos({ status }, { skip, take, orderBy }) {
  const where = {};
  if (status) where.status = status;
  else where.status = 'ACTIVE';

  const [rows, total] = await Promise.all([
    prisma.sosAlert.findMany({
      where,
      skip,
      take,
      orderBy: orderBy || { createdAt: 'desc' },
      include: {
        user: { select: { id: true, fullName: true, mobileNumber: true, role: true } },
      },
    }),
    prisma.sosAlert.count({ where }),
  ]);

  // Attach the related booking (if any) for situational context.
  const withBookings = await Promise.all(
    rows.map(async (sos) => {
      if (!sos.bookingId) return { ...sos, booking: null };
      const booking = await prisma.booking.findUnique({
        where: { id: sos.bookingId },
        include: { companion: { include: { user: { select: { id: true, fullName: true, mobileNumber: true } } } } },
      });
      return { ...sos, booking: booking ? serializeBooking(booking) : null };
    }),
  );

  return { items: withBookings, total };
}

export async function resolveSos(id, note, adminId) {
  const sos = await prisma.sosAlert.findUnique({ where: { id } });
  if (!sos) throw ApiError.notFound('SOS alert not found');
  if (sos.status !== 'ACTIVE') {
    throw ApiError.conflict(`SOS alert already ${sos.status}`);
  }

  const updated = await prisma.sosAlert.update({
    where: { id },
    data: {
      status: 'RESOLVED',
      resolvedById: adminId,
      resolvedAt: new Date(),
      message: note ? `${sos.message ? `${sos.message} | ` : ''}Resolved: ${note}` : sos.message,
    },
  });

  await notify(sos.userId, {
    type: 'SOS',
    title: 'Help on the way',
    body: 'Your SOS alert has been received and resolved by our safety team.',
    data: { action: 'sos_resolved', sosId: id },
  }).catch((err) => logger.debug(`[admin] sos notify skipped: ${err.message}`));

  logger.info(`[admin] sos ${id} resolved by admin ${adminId}`);
  return updated;
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

export async function listSettings() {
  const rows = await prisma.setting.findMany({ orderBy: { key: 'asc' } });
  return rows;
}

const NUMERIC_SETTINGS = new Set([
  'commission_rate',
  'referral_reward',
  'min_payout',
  'home_category_icon_size',
]);

export async function updateSetting(key, value, description, adminId) {
  let nextValue = value;

  // Coerce + sanity-check known numeric settings so money math stays valid.
  if (NUMERIC_SETTINGS.has(key)) {
    const n = Number(value);
    if (!Number.isFinite(n) || n < 0) {
      throw ApiError.badRequest(`Setting "${key}" must be a non-negative number`);
    }
    if (key === 'commission_rate' && n > 100) {
      throw ApiError.badRequest('commission_rate must be between 0 and 100');
    }
    if (key === 'home_category_icon_size' && (n < 30 || n > 100)) {
      throw ApiError.badRequest('home_category_icon_size must be between 30 and 100');
    }
    nextValue = n;
  }

  // Payment method toggles: normalise to { razorpay, cash } booleans and never
  // allow zero enabled methods (the app would have no way to pay).
  if (key === 'payment_methods') {
    const v = value && typeof value === 'object' ? value : {};
    const normalized = {
      razorpay: v.razorpay !== false,
      cash: v.cash !== false,
    };
    if (!normalized.razorpay && !normalized.cash) {
      throw ApiError.badRequest('At least one payment method must be enabled');
    }
    nextValue = normalized;
  }

  const row = await setSetting(key, nextValue, { description, updatedById: adminId });
  logger.info(`[admin] setting "${key}" updated by admin ${adminId}`);
  return row;
}

export default {
  login,
  getAdminById,
  presentAdmin,
  getDashboard,
  getRevenueSeries,
  getAnalyticsOverview,
  listUsers,
  getUserDetail,
  blockUser,
  unblockUser,
  listCompanions,
  getCompanionDetail,
  approveCompanion,
  rejectCompanion,
  suspendCompanion,
  featureCompanion,
  listKyc,
  approveKyc,
  rejectKyc,
  listBookings,
  getBookingDetail,
  startBooking,
  cancelBooking,
  refundBooking,
  listPosts,
  getPostDetail,
  removePost,
  listPayments,
  listPayouts,
  processPayout,
  rejectPayout,
  listReports,
  resolveReport,
  listTickets,
  getTicketDetail,
  replyToTicket,
  updateTicketStatus,
  listSos,
  resolveSos,
  listSettings,
  updateSetting,
};
