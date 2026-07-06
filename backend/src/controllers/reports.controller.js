// Thin HTTP handlers for the reports / safety domain.
import { asyncHandler } from '../utils/asyncHandler.js';
import { ok, created } from '../utils/apiResponse.js';
import { getPagination, buildMeta } from '../utils/pagination.js';
import * as reportsService from '../services/reports.service.js';

/** POST /reports — file a complaint. */
export const create = asyncHandler(async (req, res) => {
  const report = await reportsService.createReport({
    reporterId: req.user.id,
    reportedUserId: req.body.reportedUserId,
    bookingId: req.body.bookingId,
    category: req.body.category,
    description: req.body.description,
  });
  return created(res, report);
});

/** GET /reports/mine — reports filed by the current user. */
export const listMine = asyncHandler(async (req, res) => {
  const { skip, take, page, limit } = getPagination(req);
  const { data, total } = await reportsService.listMyReports({
    reporterId: req.user.id,
    skip,
    take,
  });
  return ok(res, data, buildMeta(total, page, limit));
});

export default { create, listMine };
