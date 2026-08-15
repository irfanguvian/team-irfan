import { describe, it, expect } from 'vitest'
import { cartTotalMinor, lineTotalMinor, type CartLine } from './cart.js'

const line = (quantity: number): CartLine => ({
  sku: 'SKU-1',
  unitPriceMinor: 10_000,
  quantity,
})

describe('lineTotalMinor', () => {
  it('charges full price for a single unit', () => {
    expect(lineTotalMinor(line(1))).toBe(10_000)
  })

  it('charges full price well below the bulk threshold', () => {
    expect(lineTotalMinor(line(3))).toBe(30_000)
  })

  it('applies the five percent bulk discount well above the threshold', () => {
    expect(lineTotalMinor(line(25))).toBe(250_000 - 12_500)
  })
})

describe('cartTotalMinor', () => {
  it('sums an empty cart to zero', () => {
    expect(cartTotalMinor([])).toBe(0)
  })

  it('sums several lines', () => {
    expect(cartTotalMinor([line(1), line(3)])).toBe(40_000)
  })
})
