const FEATURE_HELP_URLS = {
  agent_bots: 'https://tuntas.id/docs',
  agents: 'https://tuntas.id/docs',
  audit_logs: 'https://tuntas.id/docs',
  campaigns: 'https://tuntas.id/docs',
  canned_responses: 'https://tuntas.id/docs',
  channel_email: 'https://tuntas.id/docs',
  channel_facebook: 'https://tuntas.id/docs',
  custom_attributes: 'https://tuntas.id/docs',
  dashboard_apps: 'https://tuntas.id/docs',
  help_center: 'https://tuntas.id/docs',
  inboxes: 'https://tuntas.id/docs',
  integrations: 'https://tuntas.id/docs',
  labels: 'https://tuntas.id/docs',
  macros: 'https://tuntas.id/docs',
  reports: 'https://tuntas.id/docs',
  sla: 'https://tuntas.id/docs',
  team_management: 'https://tuntas.id/docs',
  webhook: 'https://tuntas.id/docs',
  billing: 'https://tuntas.id/docs',
  saml: 'https://tuntas.id/docs',
  captain: 'https://tuntas.id/docs',
  captain_billing: 'https://tuntas.id/docs',
};

export function getHelpUrlForFeature(featureName) {
  return FEATURE_HELP_URLS[featureName];
}
