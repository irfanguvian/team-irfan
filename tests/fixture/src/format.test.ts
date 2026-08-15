import { describe, it, expect } from 'vitest'
import { formatMinor } from './format.js'

describe('formatMinor', () => {
  it('renders minor units as a major amount with two decimals', () => {
    expect(formatMinor(123_456)).toBe('IDR 1,234.56')
  })

  it('pads a single trailing minor digit', () => {
    expect(formatMinor(105)).toBe('IDR 1.05')
  })

  it('keeps the sign in front of the currency amount', () => {
    expect(formatMinor(-250)).toBe('-IDR 2.50')
  })

  it('rejects a fractional minor amount', () => {
    expect(() => formatMinor(1.5)).toThrow(TypeError)
  })
})
