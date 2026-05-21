require "rails_helper"

RSpec.describe Pito::Notifications::Formatter::Templates::YoutubeReauthNeeded do
  let(:payload) do
    {
      "connection_id"    => 12,
      "connection_email" => "creator@example.com"
    }
  end
  let(:notification) do
    build_stubbed(:notification, :youtube_reauth_needed, event_payload: payload)
  end
  let(:template) { described_class.new(notification) }

  describe "#title" do
    it "is `youtube re-auth needed: <email>`" do
      expect(template.title).to eq("youtube re-auth needed: creator@example.com")
    end
  end

  describe "#body" do
    it "explains and links to /oauth/youtube/start" do
      expect(template.body).to include("creator@example.com")
      expect(template.body).to include("[re-authorize](/oauth/youtube/start)")
    end
  end

  describe "#url" do
    it "is /oauth/youtube/start" do
      expect(template.url).to eq("/oauth/youtube/start")
    end
  end

  it "is graceful with empty event_payload" do
    n = build(:notification, :youtube_reauth_needed, event_payload: {})
    n.save!
    t = described_class.new(n)
    expect { t.title }.not_to raise_error
    expect { t.body }.not_to raise_error
    expect { t.url }.not_to raise_error
  end
end
