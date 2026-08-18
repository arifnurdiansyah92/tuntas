json.partial! 'api/v1/models/account', formats: [:json], resource: @account
json.latest_tuntas_version @latest_tuntas_version
json.partial! 'enterprise/api/v1/accounts/partials/account', account: @account if TuntasApp.enterprise?
