/**
 * Calendar-day bucket for an instant, as seen from a given IANA time zone.
 * Returns an ISO date string, e.g. "2026-03-03".
 */
export function dayKeyInZone(instant: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(instant);
}
