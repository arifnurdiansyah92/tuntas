require 'rails_helper'

describe TuntasHub do
  describe '.base_url' do
    it 'uses the static hub url' do
      expect(described_class::DEFAULT_BASE_URL).to eq('https://hub.2.chatwoot.com')
      expect(described_class.base_url).to eq('https://hub.2.chatwoot.com')
    end
  end

  it 'generates installation identifier' do
    installation_identifier = described_class.installation_identifier
    expect(installation_identifier).not_to be_nil
    expect(described_class.installation_identifier).to eq installation_identifier
  end

  context 'when fetching sync_with_hub' do
    it 'does not contact the hub unless ENABLE_HUB_TELEMETRY is set' do
      allow(RestClient).to receive(:post)
      expect(described_class.sync_with_hub).to be_nil
      expect(RestClient).not_to have_received(:post)
    end

    it 'gets latest version from the hub when telemetry is enabled' do
      version = '1.1.1'
      with_modified_env ENABLE_HUB_TELEMETRY: 'true' do
        allow(RestClient).to receive(:post).and_return({ version: version }.to_json)
        expect(described_class.sync_with_hub['version']).to eq version
        expect(RestClient).to have_received(:post).with(described_class.ping_url, described_class.instance_config
          .merge(described_class.instance_metrics).to_json, { content_type: :json, accept: :json })
      end
    end

    it 'will not send instance metrics when DISABLE_TELEMETRY is also set' do
      version = '1.1.1'
      with_modified_env ENABLE_HUB_TELEMETRY: 'true', DISABLE_TELEMETRY: 'true' do
        allow(RestClient).to receive(:post).and_return({ version: version }.to_json)
        expect(described_class.sync_with_hub['version']).to eq version
        expect(RestClient).to have_received(:post).with(described_class.ping_url,
                                                        described_class.instance_config.to_json, { content_type: :json, accept: :json })
      end
    end

    it 'returns nil when the hub is down' do
      with_modified_env ENABLE_HUB_TELEMETRY: 'true' do
        allow(RestClient).to receive(:post).and_raise(ExceptionList::REST_CLIENT_EXCEPTIONS.sample)
        expect(described_class.sync_with_hub).to be_nil
      end
    end
  end

  context 'when register instance' do
    let(:company_name) { 'test' }
    let(:owner_name) { 'test' }
    let(:owner_email) { 'test@test.com' }

    it 'does not send registration unless ENABLE_HUB_TELEMETRY is set' do
      allow(RestClient).to receive(:post)
      described_class.register_instance(company_name, owner_name, owner_email)
      expect(RestClient).not_to have_received(:post)
    end

    it 'sends info of registration when telemetry is enabled' do
      with_modified_env ENABLE_HUB_TELEMETRY: 'true' do
        info = { company_name: company_name, owner_name: owner_name, owner_email: owner_email, subscribed_to_mailers: true }
        allow(RestClient).to receive(:post)
        described_class.register_instance(company_name, owner_name, owner_email)
        expect(RestClient).to have_received(:post).with(described_class.registration_url,
                                                        info.merge(described_class.instance_config).to_json, { content_type: :json, accept: :json })
      end
    end
  end

  context 'when sending events' do
    let(:event_name) { 'sample_event' }
    let(:event_data) { { 'sample_data' => 'sample_data' } }

    it 'does not send instance events unless ENABLE_HUB_TELEMETRY is set' do
      allow(RestClient).to receive(:post)
      described_class.emit_event(event_name, event_data)
      expect(RestClient).not_to have_received(:post)
    end

    it 'sends instance events when telemetry is enabled' do
      with_modified_env ENABLE_HUB_TELEMETRY: 'true' do
        info = { event_name: event_name, event_data: event_data }
        allow(RestClient).to receive(:post)
        described_class.emit_event(event_name, event_data)
        expect(RestClient).to have_received(:post).with(described_class.events_url,
                                                        info.merge(described_class.instance_config).to_json, { content_type: :json, accept: :json })
      end
    end
  end
end
