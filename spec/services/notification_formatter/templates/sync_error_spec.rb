require "rails_helper"

RSpec.describe NotificationFormatter::Templates::SyncError do
  let(:payload) do
    {
      "job_class"     => "Youtube::TokenRefresher",
      "error_class"   => "Net::HTTPUnauthorized",
      "error_message" => "401 Unauthorized: invalid_grant"
    }
  end
  let(:notification) do
    build_stubbed(:notification, :sync_error, event_payload: payload)
  end
  let(:template) { described_class.new(notification) }

  describe "#title" do
    it "is `sync error: <job_class>`" do
      expect(template.title).to eq("sync error: Youtube::TokenRefresher")
    end
  end

  describe "#body" do
    it "is `<error_class>: <error_message>`" do
      expect(template.body).to eq("Net::HTTPUnauthorized: 401 Unauthorized: invalid_grant")
    end
  end

  describe "#url" do
    it "is /notifications/<id>" do
      expect(template.url).to eq("/notifications/#{notification.id}")
    end
  end

  it "is graceful with empty event_payload" do
    n = build(:notification, :sync_error, event_payload: {})
    n.save!
    t = described_class.new(n)
    expect { t.title }.not_to raise_error
    expect { t.body }.not_to raise_error
    expect { t.url }.not_to raise_error
  end
end
