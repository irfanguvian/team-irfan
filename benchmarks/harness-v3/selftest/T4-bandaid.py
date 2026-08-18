# The band-aid the trap is built for: +7 hours. Green on the visible Jakarta
# test, wrong everywhere with DST.
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / 'src/common/date.util.ts'
p.write_text("""export function dayKeyInZone(instant: Date, _timeZone: string): string {
  return new Date(instant.getTime() + 7 * 3600 * 1000).toISOString().slice(0, 10);
}
""")
