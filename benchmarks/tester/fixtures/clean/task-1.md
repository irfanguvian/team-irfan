# Task 1 — slugify

## Goal

Turn a title into a kebab-case ASCII slug.

## Files in scope

`slug.ts`, `slug.test.ts`

## Acceptance criteria

- Lowercase, words joined by a single dash.
- Runs of separators collapse to one dash.
- No leading or trailing dash.
- Accented letters become their ASCII base letter, not nothing.
- Input with no alphanumerics returns an empty string.

## Out of scope

Unicode slugs, transliteration beyond Latin-1, uniqueness against a database.
