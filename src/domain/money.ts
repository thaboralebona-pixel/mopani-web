// Money is handled in integer cents. Server values are the authority; this module only parses and displays them.
export type Cents = number;

const RAND_PATTERN = /^\d{1,9}(\.\d{1,2})?$/;

/** Converts a server rand value (number or decimal string) to integer cents. Returns null for anything malformed or negative. */
export function toCents(value: unknown): Cents | null {
  let n: number;
  if (typeof value === 'number') {
    n = value;
  } else if (typeof value === 'string' && RAND_PATTERN.test(value.trim())) {
    n = Number(value.trim());
  } else {
    return null;
  }
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.round(n * 100);
}

/** Formats integer cents for display, for example 18000 becomes "R180.00". */
export function formatRand(cents: Cents): string {
  const whole = Math.floor(cents / 100);
  const remainder = String(cents % 100).padStart(2, '0');
  return `R${whole}.${remainder}`;
}
