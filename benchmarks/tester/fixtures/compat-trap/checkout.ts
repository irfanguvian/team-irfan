import { formatMinor } from './format.js'

export type CheckoutSummary = { totalMinor: number; display: string }

/**
 * Pre-existing shipped endpoint, written against the OLD formatMinor contract
 * (which rendered the currency prefix itself). Its display is pinned by the
 * contract test below — under the changed formatter it breaks.
 */
export function checkoutSummary(totalMinor: number): CheckoutSummary {
  return { totalMinor, display: formatMinor(totalMinor) }
}
