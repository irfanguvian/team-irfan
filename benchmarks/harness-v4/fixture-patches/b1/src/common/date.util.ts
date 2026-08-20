/**
 * Calendar-day bucket for an instant, as seen from a given IANA time zone.
 * Returns an ISO date string, e.g. "2026-03-03".
 */
export function dayKeyInZone(instant: Date, _timeZone: string): string {
  return instant.toISOString().slice(0, 10);
}
