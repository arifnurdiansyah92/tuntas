import { useConfig } from '../useConfig';

describe('useConfig', () => {
  const originalTuntasConfig = window.tuntasConfig;

  beforeEach(() => {
    window.tuntasConfig = {
      hostURL: 'https://example.com',
      vapidPublicKey: 'vapid-key',
      enabledLanguages: ['en', 'fr'],
      isEnterprise: 'true',
      enterprisePlanName: 'enterprise',
    };
  });

  afterEach(() => {
    window.tuntasConfig = originalTuntasConfig;
  });

  it('returns the correct configuration values', () => {
    const config = useConfig();

    expect(config.hostURL).toBe('https://example.com');
    expect(config.vapidPublicKey).toBe('vapid-key');
    expect(config.enabledLanguages).toEqual(['en', 'fr']);
    expect(config.isEnterprise).toBe(true);
    expect(config.enterprisePlanName).toBe('enterprise');
  });

  it('handles missing configuration values', () => {
    window.tuntasConfig = {};
    const config = useConfig();

    expect(config.hostURL).toBeUndefined();
    expect(config.vapidPublicKey).toBeUndefined();
    expect(config.enabledLanguages).toBeUndefined();
    expect(config.isEnterprise).toBe(false);
    expect(config.enterprisePlanName).toBeUndefined();
  });

  it('handles undefined window.tuntasConfig', () => {
    window.tuntasConfig = undefined;
    const config = useConfig();

    expect(config.hostURL).toBeUndefined();
    expect(config.vapidPublicKey).toBeUndefined();
    expect(config.enabledLanguages).toBeUndefined();
    expect(config.isEnterprise).toBe(false);
    expect(config.enterprisePlanName).toBeUndefined();
  });
});
