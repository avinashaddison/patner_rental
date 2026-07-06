// Pagination helpers. Parse ?page&limit&sort=field:dir from the request, and build
// the meta envelope returned alongside list responses.

const MAX_LIMIT = 100;

/**
 * Extract pagination + sort from a request.
 * @returns {{skip:number, take:number, page:number, limit:number, orderBy?:object}}
 */
export function getPagination(req) {
  const q = req.query || {};
  let page = parseInt(q.page, 10);
  let limit = parseInt(q.limit, 10);
  if (!Number.isFinite(page) || page < 1) page = 1;
  if (!Number.isFinite(limit) || limit < 1) limit = 20;
  if (limit > MAX_LIMIT) limit = MAX_LIMIT;

  const result = {
    skip: (page - 1) * limit,
    take: limit,
    page,
    limit,
  };

  if (q.sort && typeof q.sort === 'string') {
    const [field, dirRaw] = q.sort.split(':');
    const dir = String(dirRaw).toLowerCase() === 'asc' ? 'asc' : 'desc';
    if (field) result.orderBy = { [field]: dir };
  }

  return result;
}

/**
 * Build the meta object for a paginated response.
 * @returns {{page:number, limit:number, total:number, totalPages:number, hasMore:boolean}}
 */
export function buildMeta(total, page, limit) {
  const totalPages = limit > 0 ? Math.ceil(total / limit) : 0;
  return {
    page,
    limit,
    total,
    totalPages,
    hasMore: page < totalPages,
  };
}

export default { getPagination, buildMeta };
