import { describe, it, expect } from 'vitest'
import { discountedTotalMinor } from './discount.js'

// Every case here passes. None of them is at the threshold, which is where the
// acceptance criterion actually lives.
describe('discountedTotalMinor', () => {
  it('charges full price for a single unit', () => {
    expect(discountedTotalMinor(10_000, 1)).toBe(10_000)
  })

  it('charges full price well below the threshold', () => {
    expect(discountedTotalMinor(10_000, 3)).toBe(30_000)
  })

  it('applies the discount well above the threshold', () => {
    expect(discountedTotalMinor(10_000, 25)).toBe(250_000 - 12_500)
  })
})
