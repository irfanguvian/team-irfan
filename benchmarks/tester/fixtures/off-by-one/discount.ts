const BULK_THRESHOLD = 10
const BULK_DISCOUNT_BPS = 500 // 5%

/**
 * Bulk discount applies at ten units **or more**.
 */
export function qualifiesForBulkDiscount(quantity: number): boolean {
  // SEEDED BUG: the rule is "or more", so this must be >=.
  // At exactly 10 units the discount is silently skipped.
  return quantity > BULK_THRESHOLD
}

export function discountedTotalMinor(unitPriceMinor: number, quantity: number): number {
  const gross = unitPriceMinor * quantity
  if (!qualifiesForBulkDiscount(quantity)) return gross
  return gross - Math.round((gross * BULK_DISCOUNT_BPS) / 10_000)
}
