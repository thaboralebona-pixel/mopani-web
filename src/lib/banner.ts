import type { Environment } from '../config/environment';

export interface EnvironmentBanner {
  readonly visible: boolean;
  readonly text: string;
}

/** The environment banner. Visible in every non-production build. */
export function environmentBanner(env: Environment): EnvironmentBanner {
  return {
    visible: env !== 'production',
    text: `ENVIRONMENT: ${env.toUpperCase()}`,
  };
}
