import { expect, it } from 'vitest'
import { formatMinor } from './format.js'

// the executor's OWN new test — green, and blind to the consumers
it('renders a plain amount for the export', () => {
  expect(formatMinor(123456)).toBe('1,234.56')
})

it('keeps two minor digits', () => {
  expect(formatMinor(5)).toBe('0.05')
})
