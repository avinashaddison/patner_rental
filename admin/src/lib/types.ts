/**
 * Admin-panel domain types.
 *
 * These mirror the JSON shapes the backend admin API serializes (see
 * backend/src/services/admin.service.js serializers and docs/DATA_MODEL.md).
 * Decimal money fields arrive as numbers (the serializers coerce them).
 * Fields are intentionally permissive (`?`) because list vs. detail endpoints
 * include different relations.
 */

export type Role = 'CUSTOMER' | 'COMPANION' | 'ADMIN';
export type Gender = 'MALE' | 'FEMALE' | 'OTHER';
export type KycStatus = 'PENDING' | 'SUBMITTED' | 'APPROVED' | 'REJECTED';
export type KycDocType = 'GOVERNMENT_ID' | 'SELFIE';
export type CompanionStatus = 'PENDING' | 'APPROVED' | 'REJECTED' | 'SUSPENDED';
export type BookingStatus =
  | 'PENDING'
  | 'CONFIRMED'
  | 'IN_PROGRESS'
  | 'COMPLETED'
  | 'CANCELLED'
  | 'REFUNDED';
export type PostStatus = 'PUBLISHED' | 'REMOVED';
export type ReportCategory = 'HARASSMENT' | 'FAKE_PROFILE' | 'ABUSE' | 'SPAM' | 'OTHER';
export type ReportStatus = 'OPEN' | 'REVIEWING' | 'RESOLVED' | 'DISMISSED';
export type PaymentStatus = 'CREATED' | 'AUTHORIZED' | 'CAPTURED' | 'FAILED' | 'REFUNDED';
export type PayoutMethod = 'BANK_TRANSFER' | 'UPI';
export type PayoutStatus =
  | 'REQUESTED'
  | 'PROCESSING'
  | 'COMPLETED'
  | 'FAILED'
  | 'REJECTED';
export type TransactionType =
  | 'CREDIT'
  | 'DEBIT'
  | 'PAYOUT'
  | 'REFUND'
  | 'COMMISSION'
  | 'REFERRAL_REWARD'
  | 'BOOKING_EARNING';

/** users (serializeUser / serializeUserLite). */
export interface AdminUser {
  id: string;
  mobileNumber: string;
  fullName: string;
  gender?: Gender;
  dateOfBirth?: string | null;
  city?: string | null;
  email?: string | null;
  username?: string | null;
  role: Role;
  isMobileVerified?: boolean;
  profilePhotoUrl?: string | null;
  isBlocked: boolean;
  blockedReason?: string | null;
  referralCode?: string;
  referredById?: string | null;
  lastActiveAt?: string | null;
  createdAt: string;
  updatedAt?: string;
  /** Derived server-side. */
  age?: number | null;
  isCompanion?: boolean;
  companion?: AdminCompanion;
  wallet?: AdminWallet;
  counts?: {
    bookingsAsCustomer?: number;
    payouts?: number;
    reviews?: number;
    reportsReceived?: number;
    sosAlerts?: number;
  };
  /** Present on the user-detail endpoint. */
  kycDocuments?: AdminKycDocument[];
  recentBookings?: AdminBooking[];
}

export interface AdminWallet {
  id: string;
  userId: string;
  balance: number;
  pendingBalance: number;
  totalEarned: number;
  totalWithdrawn: number;
  currency?: string;
}

export interface CompanionPhoto {
  id: string;
  photoUrl: string;
  isPrimary: boolean;
  sortOrder?: number;
}

export interface Category {
  id: string;
  slug: string;
  name: string;
  iconUrl?: string | null;
  sortOrder?: number;
  isActive?: boolean;
}

export interface CompanionAvailability {
  id: string;
  dayOfWeek: number;
  startTime: string;
  endTime: string;
  isAvailable: boolean;
}

/** companions (serializeCompanion). */
export interface AdminCompanion {
  id: string;
  userId: string;
  aboutMe?: string | null;
  languages?: string[];
  interests?: string[];
  hourlyRate: number;
  city?: string | null;
  status: CompanionStatus;
  isOnline?: boolean;
  ratingAvg?: number;
  ratingCount?: number;
  totalBookings?: number;
  totalEarnings?: number;
  isFeatured?: boolean;
  latitude?: number | null;
  longitude?: number | null;
  approvedAt?: string | null;
  rejectedReason?: string | null;
  createdAt: string;
  updatedAt?: string;
  /** Derived. */
  name?: string | null;
  age?: number | null;
  isVerified?: boolean;
  user?: AdminUser;
  photos?: CompanionPhoto[];
  categories?: Category[];
  availability?: CompanionAvailability[];
  counts?: { bookings?: number; reviews?: number };
  /** Present on companion-detail endpoint. */
  kyc?: {
    approved: boolean;
    documents: AdminKycDocument[];
  };
}

/** kyc_documents (serializeKycDoc). */
export interface AdminKycDocument {
  id: string;
  userId: string;
  docType: KycDocType;
  documentUrl: string;
  documentNumber?: string | null;
  status: KycStatus;
  reviewedById?: string | null;
  reviewNotes?: string | null;
  reviewedAt?: string | null;
  createdAt: string;
  user?: AdminUser;
}

/** booking_status_history entry (serializeBookingStatus). */
export interface AdminBookingStatusEntry {
  id: string;
  bookingId?: string;
  status: BookingStatus;
  changedById?: string | null;
  note?: string | null;
  createdAt: string;
}

/** bookings (serializeBooking, trimmed to what admin pages render). */
export interface AdminBooking {
  id: string;
  bookingCode: string;
  customerId: string;
  companionId: string;
  categoryId?: string | null;
  activity: string;
  durationHours: number;
  bookingDate: string;
  startTime: string;
  endTime?: string;
  meetingLocation: string;
  meetingPlaceType: string;
  /** Money breakdown (Decimal → number, snapshots taken at booking time). */
  hourlyRate?: number;
  totalAmount: number;
  commissionRate?: number;
  commissionAmount?: number;
  companionPayout?: number;
  status: BookingStatus;
  notes?: string | null;
  /** Meet-at-location start verification (customer reveals code to companion). */
  startCode?: string | null;
  startCodeAttempts?: number;
  startedAt?: string | null;
  startVerifiedById?: string | null;
  cancelledById?: string | null;
  cancellationReason?: string | null;
  createdAt: string;
  updatedAt?: string;
  completedAt?: string | null;
  customer?: AdminUser;
  companion?: AdminCompanion;
  category?: Category | null;
  payment?: AdminPayment | null;
  /** Present on the booking-detail endpoint. */
  statusHistory?: AdminBookingStatusEntry[];
}

/** posts (serializePost — companion photo posts surfaced in feeds). */
export interface AdminPost {
  id: string;
  companionId: string;
  caption?: string | null;
  /** R2 public image URLs (carousel). */
  images: string[];
  status: PostStatus;
  likeCount: number;
  commentCount: number;
  createdAt: string;
  updatedAt?: string;
  companion?: {
    id: string;
    status: string;
    name?: string | null;
    mobileNumber?: string | null;
    userId?: string | null;
  } | null;
}

/** payments (serializePayment). */
export interface AdminPayment {
  id: string;
  bookingId: string;
  customerId: string;
  razorpayOrderId?: string | null;
  razorpayPaymentId?: string | null;
  razorpaySignature?: string | null;
  amount: number;
  currency?: string;
  status: PaymentStatus;
  method?: string;
  capturedAt?: string | null;
  createdAt: string;
  updatedAt?: string;
  booking?: AdminBooking;
  customer?: Pick<AdminUser, 'id' | 'fullName' | 'mobileNumber' | 'email'>;
}

/** payouts (serializePayout). */
export interface AdminPayout {
  id: string;
  userId: string;
  amount: number;
  method: PayoutMethod;
  bankAccountName?: string | null;
  bankAccountNumber?: string | null;
  ifsc?: string | null;
  upiId?: string | null;
  status: PayoutStatus;
  processedById?: string | null;
  notes?: string | null;
  processedAt?: string | null;
  createdAt: string;
  updatedAt?: string;
  user?: Pick<AdminUser, 'id' | 'fullName' | 'mobileNumber' | 'email'> & {
    wallet?: AdminWallet;
  };
}

/** reports (admin list/detail). */
export interface AdminReport {
  id: string;
  reporterId: string;
  reportedUserId: string;
  bookingId?: string | null;
  category: ReportCategory;
  description?: string | null;
  status: ReportStatus;
  resolutionNotes?: string | null;
  resolvedAt?: string | null;
  createdAt: string;
  reporter?: Pick<AdminUser, 'id' | 'fullName' | 'mobileNumber' | 'role'>;
  reportedUser?: Pick<AdminUser, 'id' | 'fullName' | 'mobileNumber' | 'role'>;
}

export type TicketStatus = 'OPEN' | 'IN_PROGRESS' | 'RESOLVED' | 'CLOSED';
export type TicketPriority = 'LOW' | 'MEDIUM' | 'HIGH' | 'URGENT';

/** ticket_messages (serializeTicketMessage). */
export interface AdminTicketMessage {
  id: string;
  ticketId: string;
  senderId: string;
  message: string;
  createdAt: string;
  sender?: Pick<AdminUser, 'id' | 'fullName' | 'role'>;
}

/** support_tickets (admin list/detail). */
export interface AdminSupportTicket {
  id: string;
  userId: string;
  subject: string;
  description: string;
  status: TicketStatus;
  priority: TicketPriority;
  assignedToId?: string | null;
  resolvedAt?: string | null;
  createdAt: string;
  updatedAt?: string;
  user?: Pick<AdminUser, 'id' | 'fullName' | 'mobileNumber' | 'email' | 'role'>;
  /** Present on the ticket-detail endpoint. */
  messages?: AdminTicketMessage[];
  /** List endpoint: true when the last message is from the user (needs a reply). */
  awaitingReply?: boolean;
}

/** settings (key/value runtime config — DATA_MODEL.md → settings). */
export interface AdminSetting {
  id: string;
  key: string;
  /** JSON value — number, string, boolean, or array depending on the key. */
  value: unknown;
  description?: string | null;
  updatedById?: string | null;
  updatedAt?: string;
}

/** KPIs from `GET /admin/analytics/overview` (extra fields tolerated). */
export interface AnalyticsOverview {
  totalRevenue?: number;
  totalCommission?: number;
  totalBookings?: number;
  completedBookings?: number;
  activeBookings?: number;
  totalUsers?: number;
  totalCustomers?: number;
  totalCompanions?: number;
  activeCompanions?: number;
  newUsers?: number;
  avgBookingValue?: number;
  avgRating?: number;
  conversionRate?: number;
  revenueDelta?: number;
  bookingsDelta?: number;
  usersDelta?: number;
  companionsDelta?: number;
}
