// Idempotent database seed.
// Seeds: 7 categories, runtime settings, one admin, a demo customer, and 3 APPROVED
// demo companions (with photos, categories, availability, wallet, approved KYC).
import { PrismaClient, Prisma } from '@prisma/client';
import bcrypt from 'bcryptjs';
import { customAlphabet } from 'nanoid';

const prisma = new PrismaClient();

const ADMIN_EMAIL = process.env.SEED_ADMIN_EMAIL || 'admin@companionranchi.com';
const ADMIN_PASSWORD = process.env.SEED_ADMIN_PASSWORD || 'Admin@12345';
const DEFAULT_CITY = process.env.DEFAULT_CITY || 'Ranchi';

const refCode = customAlphabet('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 8);

const CATEGORIES = [
  { slug: 'coffee-partner', name: 'Coffee Partner', sortOrder: 1 },
  { slug: 'movie-partner', name: 'Movie Partner', sortOrder: 2 },
  { slug: 'shopping-partner', name: 'Shopping Partner', sortOrder: 3 },
  { slug: 'event-companion', name: 'Event Companion', sortOrder: 4 },
  { slug: 'city-guide', name: 'City Guide', sortOrder: 5 },
  { slug: 'travel-companion', name: 'Travel Companion', sortOrder: 6 },
  { slug: 'networking-partner', name: 'Networking Partner', sortOrder: 7 },
];

const SETTINGS = [
  { key: 'commission_rate', value: 20, description: 'Platform commission percent' },
  { key: 'referral_reward', value: 100, description: 'Referral reward in INR' },
  { key: 'min_payout', value: 500, description: 'Minimum payout amount in INR' },
  { key: 'booking_durations', value: [1, 2, 4, 6], description: 'Allowed booking durations (hours)' },
  { key: 'cities', value: ['Ranchi'], description: 'Operating cities' },
];

function dob(age) {
  const d = new Date();
  d.setFullYear(d.getFullYear() - age);
  return d;
}

async function seedCategories() {
  const out = {};
  for (const c of CATEGORIES) {
    const cat = await prisma.category.upsert({
      where: { slug: c.slug },
      create: { slug: c.slug, name: c.name, sortOrder: c.sortOrder, isActive: true },
      update: { name: c.name, sortOrder: c.sortOrder, isActive: true },
    });
    out[c.slug] = cat;
  }
  console.log(`Seeded ${CATEGORIES.length} categories.`);
  return out;
}

async function seedSettings() {
  for (const s of SETTINGS) {
    await prisma.setting.upsert({
      where: { key: s.key },
      create: { key: s.key, value: s.value, description: s.description },
      update: { value: s.value, description: s.description },
    });
  }
  console.log(`Seeded ${SETTINGS.length} settings.`);
}

async function seedAdmin() {
  const passwordHash = await bcrypt.hash(ADMIN_PASSWORD, 10);
  const admin = await prisma.adminUser.upsert({
    where: { email: ADMIN_EMAIL },
    create: {
      email: ADMIN_EMAIL,
      passwordHash,
      name: 'Super Admin',
      role: 'SUPER_ADMIN',
      permissions: ['*'],
      isActive: true,
    },
    update: { passwordHash, role: 'SUPER_ADMIN', isActive: true },
  });
  console.log(`Seeded admin: ${admin.email}`);
  return admin;
}

async function ensureWallet(userId) {
  await prisma.wallet.upsert({
    where: { userId },
    create: { userId },
    update: {},
  });
}

async function seedCustomer() {
  const mobile = '+919000000001';
  const user = await prisma.user.upsert({
    where: { mobileNumber: mobile },
    create: {
      mobileNumber: mobile,
      fullName: 'Demo Customer',
      gender: 'MALE',
      dateOfBirth: dob(28),
      city: DEFAULT_CITY,
      email: 'customer@companionranchi.com',
      role: 'CUSTOMER',
      isMobileVerified: true,
      referralCode: 'DEMOCUST',
    },
    update: { isMobileVerified: true },
  });
  await ensureWallet(user.id);
  console.log(`Seeded demo customer: ${user.mobileNumber}`);
  return user;
}

const COMPANIONS = [
  {
    mobile: '+919000000101',
    name: 'Aisha Verma',
    gender: 'FEMALE',
    age: 24,
    aboutMe: 'Friendly coffee and movie companion. Love good conversation and exploring Ranchi cafes.',
    languages: ['Hindi', 'English'],
    interests: ['Coffee', 'Movies', 'Music', 'Reading'],
    hourlyRate: 600,
    categories: ['coffee-partner', 'movie-partner', 'city-guide'],
    isFeatured: true,
    photos: [
      'https://randomuser.me/api/portraits/women/68.jpg',
      'https://picsum.photos/seed/aisha1/600/800',
    ],
    rating: 4.8,
    ratingCount: 42,
  },
  {
    mobile: '+919000000102',
    name: 'Rahul Singh',
    gender: 'MALE',
    age: 27,
    aboutMe: 'City guide and networking partner. Happy to show you around or accompany you to events.',
    languages: ['Hindi', 'English', 'Bengali'],
    interests: ['Travel', 'Networking', 'Food', 'Photography'],
    hourlyRate: 500,
    categories: ['city-guide', 'networking-partner', 'travel-companion'],
    isFeatured: true,
    photos: [
      'https://randomuser.me/api/portraits/men/32.jpg',
      'https://picsum.photos/seed/rahul1/600/800',
    ],
    rating: 4.6,
    ratingCount: 31,
  },
  {
    mobile: '+919000000103',
    name: 'Priya Kumari',
    gender: 'FEMALE',
    age: 25,
    aboutMe: 'Shopping and event companion. Great taste, great company for malls and public events.',
    languages: ['Hindi', 'English'],
    interests: ['Shopping', 'Events', 'Fashion', 'Coffee'],
    hourlyRate: 700,
    categories: ['shopping-partner', 'event-companion', 'coffee-partner'],
    isFeatured: false,
    photos: [
      'https://randomuser.me/api/portraits/women/44.jpg',
      'https://picsum.photos/seed/priya1/600/800',
    ],
    rating: 4.9,
    ratingCount: 58,
  },
];

async function seedCompanion(spec, categoryMap, admin) {
  const user = await prisma.user.upsert({
    where: { mobileNumber: spec.mobile },
    create: {
      mobileNumber: spec.mobile,
      fullName: spec.name,
      gender: spec.gender,
      dateOfBirth: dob(spec.age),
      city: DEFAULT_CITY,
      role: 'COMPANION',
      isMobileVerified: true,
      profilePhotoUrl: spec.photos[0],
      referralCode: refCode(),
    },
    update: { fullName: spec.name, profilePhotoUrl: spec.photos[0], role: 'COMPANION' },
  });

  await ensureWallet(user.id);

  const companion = await prisma.companion.upsert({
    where: { userId: user.id },
    create: {
      userId: user.id,
      aboutMe: spec.aboutMe,
      languages: spec.languages,
      interests: spec.interests,
      hourlyRate: new Prisma.Decimal(spec.hourlyRate),
      city: DEFAULT_CITY,
      status: 'APPROVED',
      isOnline: false,
      ratingAvg: spec.rating,
      ratingCount: spec.ratingCount,
      isFeatured: spec.isFeatured,
      latitude: 23.3441,
      longitude: 85.3096,
      approvedAt: new Date(),
    },
    update: {
      aboutMe: spec.aboutMe,
      languages: spec.languages,
      interests: spec.interests,
      hourlyRate: new Prisma.Decimal(spec.hourlyRate),
      status: 'APPROVED',
      ratingAvg: spec.rating,
      ratingCount: spec.ratingCount,
      isFeatured: spec.isFeatured,
      approvedAt: new Date(),
    },
  });

  // Photos (reset + recreate for idempotency).
  await prisma.companionPhoto.deleteMany({ where: { companionId: companion.id } });
  for (let i = 0; i < spec.photos.length; i += 1) {
    await prisma.companionPhoto.create({
      data: {
        companionId: companion.id,
        photoUrl: spec.photos[i],
        isPrimary: i === 0,
        sortOrder: i,
      },
    });
  }

  // Categories.
  for (const slug of spec.categories) {
    const cat = categoryMap[slug];
    if (!cat) continue;
    await prisma.companionCategory.upsert({
      where: { companionId_categoryId: { companionId: companion.id, categoryId: cat.id } },
      create: { companionId: companion.id, categoryId: cat.id },
      update: {},
    });
  }

  // Availability: Mon–Sun 10:00–20:00.
  await prisma.companionAvailability.deleteMany({ where: { companionId: companion.id } });
  for (let day = 0; day < 7; day += 1) {
    await prisma.companionAvailability.create({
      data: {
        companionId: companion.id,
        dayOfWeek: day,
        startTime: '10:00',
        endTime: '20:00',
        isAvailable: true,
      },
    });
  }

  // Approved KYC docs (GOVERNMENT_ID + SELFIE).
  const docTypes = ['GOVERNMENT_ID', 'SELFIE'];
  for (const docType of docTypes) {
    const existing = await prisma.kycDocument.findFirst({
      where: { userId: user.id, docType },
    });
    if (!existing) {
      await prisma.kycDocument.create({
        data: {
          userId: user.id,
          docType,
          documentUrl: `https://picsum.photos/seed/kyc-${user.id}-${docType}/600/400`,
          documentNumber: docType === 'GOVERNMENT_ID' ? 'XXXX-XXXX-1234' : null,
          status: 'APPROVED',
          reviewedById: admin.id,
          reviewedAt: new Date(),
          reviewNotes: 'Seed-approved',
        },
      });
    }
  }

  console.log(`Seeded companion: ${spec.name} (${spec.mobile})`);
  return companion;
}

async function main() {
  console.log('Seeding Companion Ranchi database...');
  const categoryMap = await seedCategories();
  await seedSettings();
  const admin = await seedAdmin();
  await seedCustomer();
  for (const spec of COMPANIONS) {
    await seedCompanion(spec, categoryMap, admin);
  }
  console.log('Seed complete.');
}

main()
  .catch((err) => {
    console.error('Seed failed:', err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
