import { describe, expect, it } from 'vitest';
import { strings, strings2 } from './en';

// Claims the brief forbids. Matching is case-insensitive and applies to every user-facing string.
const FORBIDDEN = [
  'verified seller',
  'secured',
  'your money is held',
  'protected',
  'participating taxi',
  'youth-owned',
  'items with a photo sell more',
  'seller and driver have been credited',
  'someone will contact you shortly',
  'weighed',
  'verified weight',
  'certified',
  'guaranteed',
];

const ALL = Object.values({ ...strings, ...strings2 }) as string[];

describe('user-facing copy', () => {
  it('contains none of the forbidden claims', () => {
    for (const text of ALL) {
      for (const phrase of FORBIDDEN) {
        expect(text.toLowerCase(), `"${phrase}" found in: ${text}`).not.toContain(phrase);
      }
    }
  });

  it('never prints the production project reference', () => {
    for (const text of ALL) expect(text).not.toContain('jpjjdzlhthvookllydai');
  });
});
