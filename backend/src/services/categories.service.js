// Category admin logic: list categories and manage their (Cloudinary-hosted) icons.
// Categories themselves are seeded from src/config/constants.js; admins only edit icons.
import { prisma } from '../lib/prisma.js';
import { ApiError } from '../utils/apiResponse.js';

// Present a DB row as the API/JSON shape (matches docs contract).
function serializeCategory(category) {
  if (!category) return null;
  return {
    id: category.id,
    slug: category.slug,
    name: category.name,
    iconUrl: category.iconUrl,
    sortOrder: category.sortOrder,
    isActive: category.isActive,
  };
}

/** All categories ordered by sortOrder ascending. */
export async function listCategories() {
  const rows = await prisma.category.findMany({ orderBy: { sortOrder: 'asc' } });
  return rows.map(serializeCategory);
}

/** Fetch one category or throw 404. */
export async function getCategoryOrThrow(id) {
  const category = await prisma.category.findUnique({ where: { id } });
  if (!category) throw ApiError.notFound('Category not found');
  return category;
}

/** Set a category's icon URL. 404 if the category does not exist. */
export async function setCategoryIcon(id, iconUrl) {
  await getCategoryOrThrow(id);
  const updated = await prisma.category.update({ where: { id }, data: { iconUrl } });
  return serializeCategory(updated);
}

/** Clear a category's icon URL. 404 if the category does not exist. */
export async function clearCategoryIcon(id) {
  await getCategoryOrThrow(id);
  const updated = await prisma.category.update({ where: { id }, data: { iconUrl: null } });
  return serializeCategory(updated);
}

export default {
  listCategories,
  getCategoryOrThrow,
  setCategoryIcon,
  clearCategoryIcon,
};
