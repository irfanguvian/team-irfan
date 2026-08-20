import { expect, it } from 'vitest'
import { checkoutSummary } from './checkout.js'

// PRE-EXISTING contract test — the consumer pin. It fails under the change:
// the old formatMinor carried the currency inside the formatted string; the
// checkout display contract is exactly "IDR 1,234.56".
it('checkout summary display contract is stable', () => {
  expect(checkoutSummary(123456).display).toBe('IDR 1,234.56')
})
