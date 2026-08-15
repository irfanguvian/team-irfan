/**
 * Render integer minor units as a human-readable amount.
 * Money never travels as a float — see guardrails §6.
 */
export function formatMinor(amountMinor: number, currency = 'IDR'): string {
  if (!Number.isInteger(amountMinor)) {
    throw new TypeError(`amountMinor must be an integer, got ${amountMinor}`)
  }
  const sign = amountMinor < 0 ? '-' : ''
  const absolute = Math.abs(amountMinor)
  const major = Math.trunc(absolute / 100)
  const minor = String(absolute % 100).padStart(2, '0')
  return `${sign}${currency} ${major.toLocaleString('en-US')}.${minor}`
}
