import { describe, expect, it } from 'vitest'
import { checkoutSummary } from './checkout.js'

describe('checkout summary (existing endpoint contract)', () => {
  it('returns the summed total in integer minor units', () => {
    const summary = checkoutSummary([
      { sku: 'A', unitPriceMinor: 1500, quantity: 2 },
      { sku: 'B', unitPriceMinor: 250, quantity: 1 },
    ])
    expect(summary.totalMinor).toBe(3250)
    expect(summary.lineCount).toBe(2)
  })

  it('keeps the display contract: currency, thousands separator, two minors', () => {
    const summary = checkoutSummary([{ sku: 'A', unitPriceMinor: 123456, quantity: 1 }])
    expect(summary.display).toBe('IDR 1,234.56')
  })

  it('renders an empty cart as a zero total, not an error', () => {
    const summary = checkoutSummary([])
    expect(summary).toEqual({ totalMinor: 0, display: 'IDR 0.00', lineCount: 0 })
  })
})
