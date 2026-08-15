import { describe, it, expect } from 'vitest'
import { slugify } from './slug.js'

describe('slugify', () => {
  it('lowercases and joins words with a dash', () => {
    expect(slugify('Block Unblock User')).toBe('block-unblock-user')
  })

  it('collapses runs of separators into one dash', () => {
    expect(slugify('a  --  b')).toBe('a-b')
  })

  it('trims leading and trailing separators', () => {
    expect(slugify('  !hello!  ')).toBe('hello')
  })

  it('strips accents rather than dropping the letter', () => {
    expect(slugify('Café Déjà')).toBe('cafe-deja')
  })

  it('returns an empty string when nothing survives', () => {
    expect(slugify('!!!')).toBe('')
  })
})
