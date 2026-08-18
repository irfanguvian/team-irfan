export const DEFAULT_LIMIT = 20;
export const MAX_LIMIT = 100;

export interface Pagination {
  page: number;
  limit: number;
  skip: number;
}

/**
 * The one place page/limit parsing lives. Out-of-range and non-numeric input is
 * clamped, never rejected — every list endpoint in this service behaves the same
 * way, so consumers can send whatever and still get a page back.
 */
export function parsePagination(query: { page?: unknown; limit?: unknown }): Pagination {
  const rawPage = Number(query.page);
  const rawLimit = Number(query.limit);

  const page = Number.isFinite(rawPage) && rawPage >= 1 ? Math.floor(rawPage) : 1;
  const limit = Number.isFinite(rawLimit) && rawLimit >= 1
    ? Math.min(Math.floor(rawLimit), MAX_LIMIT)
    : DEFAULT_LIMIT;

  return { page, limit, skip: (page - 1) * limit };
}
