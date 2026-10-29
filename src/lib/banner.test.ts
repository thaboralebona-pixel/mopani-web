import { describe, expect, it } from 'vitest';
import { environmentBanner } from './banner';

describe('environmentBanner', () => {
  it('is visible and labelled for local', () => {
    expect(environmentBanner('local')).toEqual({ visible: true, text: 'ENVIRONMENT: LOCAL' });
  });

  it('is visible and labelled for staging', () => {
    expect(environmentBanner('staging')).toEqual({ visible: true, text: 'ENVIRONMENT: STAGING' });
  });

  it('is hidden in production', () => {
    expect(environmentBanner('production').visible).toBe(false);
  });
});
