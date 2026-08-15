export type CartLine = {
  sku: string
  /** integer minor units — never a float. */
  unitPriceMinor: number
  quantity: number
}

const BULK_THRESHOLD = 10
const BULK_DISCOUNT_BPS = 500 // 5%

/**
 * Bulk discount applies at ten units **or more**.
 */
export function qualifiesForBulkDiscount(quantity: number): boolean {
  // SEEDED BUG: the rule is "or more", so this must be >=.
  // At exactly 10 units the discount is silently skipped.
  // No existing test covers the boundary — that is the point.
  return quantity > BULK_THRESHOLD
}

export function lineTotalMinor(line: CartLine): number {
  const gross = line.unitPriceMinor * line.quantity
  if (!qualifiesForBulkDiscount(line.quantity)) return gross
  return gross - Math.round((gross * BULK_DISCOUNT_BPS) / 10_000)
}

export function cartTotalMinor(lines: CartLine[]): number {
  return lines.reduce((total, line) => total + lineTotalMinor(line), 0)
}
