/**
 * Kebab-case slug, ASCII only, collapsed separators, no leading or trailing dash.
 */
export function slugify(input: string): string {
  const ascii = input.normalize('NFKD').replace(/[̀-ͯ]/g, '')
  return ascii
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}
