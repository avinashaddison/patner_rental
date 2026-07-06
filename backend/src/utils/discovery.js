// Discovery matching rules shared by companion lists and the explore feed.

/**
 * Opposite-gender discovery (RentAFriend-style): male viewers are shown
 * female companions and vice versa. OTHER / unknown / logged-out viewers see
 * everyone. Applies ONLY to discovery surfaces (featured, nearby, search,
 * explore feed) — direct profile links, the following feed, chat and
 * bookings are never gender-gated.
 *
 * @param {object|null|undefined} viewer  req.user (may be absent)
 * @returns {'MALE'|'FEMALE'|null}  the companion gender to show, or null for no filter
 */
export function discoveryGenderFor(viewer) {
  if (viewer?.gender === 'MALE') return 'FEMALE';
  if (viewer?.gender === 'FEMALE') return 'MALE';
  return null;
}

export default { discoveryGenderFor };
