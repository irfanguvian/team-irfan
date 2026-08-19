import { cartTotalMinor, type CartLine } from './cart.js'
import { formatMinor } from './format.js'

export type CheckoutSummary = {
  totalMinor: number
  display: string
  lineCount: number
}

/**
 * The second endpoint: a checkout summary built on cart + format. Its test
 * asserts the EXISTING response shape and money contract, so a change that
 * passes its own new tests but alters either one breaks this endpoint —
 * the backward-compat trap the benchmarks and rule A exist to catch.
 */
export function checkoutSummary(lines: CartLine[], currency = 'IDR'): CheckoutSummary {
  const totalMinor = cartTotalMinor(lines)
  return {
    totalMinor,
    display: formatMinor(totalMinor, currency),
    lineCount: lines.length,
  }
}
