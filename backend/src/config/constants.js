// Fixed business constants. These enforce the safety policy (companionship-only,
// public-places-only) and must match docs/DATA_MODEL.md + docs/SAFETY.md.

// Activity categories. `slug` matches the seeded categories table.
export const CATEGORIES = [
  { slug: 'coffee-partner', name: 'Coffee Partner', sortOrder: 1 },
  { slug: 'movie-partner', name: 'Movie Partner', sortOrder: 2 },
  { slug: 'shopping-partner', name: 'Shopping Partner', sortOrder: 3 },
  { slug: 'event-companion', name: 'Event Companion', sortOrder: 4 },
  { slug: 'city-guide', name: 'City Guide', sortOrder: 5 },
  { slug: 'travel-companion', name: 'Travel Companion', sortOrder: 6 },
  { slug: 'networking-partner', name: 'Networking Partner', sortOrder: 7 },
];

// Allowed booking durations in hours.
export const BOOKING_DURATIONS = [1, 2, 4, 6];

// Public-place-only meeting types. Private residences / hotel rooms are NOT allowed.
export const ALLOWED_PLACE_TYPES = [
  'Mall',
  'Cafe',
  'Restaurant',
  'Public Event',
  'Park',
  'Co-working',
  'Hotel Lobby',
  'Tourist Spot',
];

// Free-text activity must validate against this companionship-only list.
export const ALLOWED_ACTIVITIES = [
  'Coffee',
  'Movie',
  'Shopping',
  'Event',
  'City Tour',
  'Travel',
  'Networking',
  'Dining',
  'Conversation',
  'Sightseeing',
  'Concert',
  'Exhibition',
  'Walk',
];

export default {
  CATEGORIES,
  BOOKING_DURATIONS,
  ALLOWED_PLACE_TYPES,
  ALLOWED_ACTIVITIES,
};
