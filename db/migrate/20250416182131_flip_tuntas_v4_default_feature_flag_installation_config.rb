class FlipTuntasV4DefaultFeatureFlagInstallationConfig < ActiveRecord::Migration[7.0]
  def up
    # Update the default feature flag config to enable tuntas_v4
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    if config && config.value.present?
      features = config.value.map do |f|
        if f['name'] == 'tuntas_v4'
          f.merge('enabled' => true)
        else
          f
        end
      end
      config.value = features
      config.save!
    end

    # Enable tuntas_v4 for all accounts in batches of 100
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('tuntas_v4') }
    end

    GlobalConfig.clear_cache
  end
end
