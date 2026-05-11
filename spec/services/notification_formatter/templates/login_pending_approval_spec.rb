require "rails_helper"

# Phase 25 — 01c. Notification template spec for the
# `login_pending_approval` event type.
RSpec.describe NotificationFormatter::Templates::LoginPendingApproval do
  let(:notification) do
    create(:notification, :with_dedup_key,
           kind: :login_pending_approval,
           event_type: "login_pending_approval",
           severity: :urgent,
           event_payload: {
             "login_attempt_id"  => 42,
             "session_id"        => 7,
             "email"             => "owner@example.test",
             "browser"           => "Firefox",
             "os"                => "Linux",
             "ip"                => "10.0.0.5",
             "ip_prefix"         => "10.0.0.0/24",
             "fingerprint_short" => "abcd1234ef56",
             "geo_summary"       => "Bucharest, RO (Bucharest)"
           })
  end

  subject(:template) { described_class.new(notification) }

  describe "#title" do
    it "renders 'new-location login: <email>'" do
      expect(template.title).to eq("new-location login: owner@example.test")
    end

    it "falls back to '(email unavailable)' when payload lacks email" do
      notification.event_payload = notification.event_payload.merge("email" => nil)
      expect(template.title).to include("(email unavailable)")
    end
  end

  describe "#body" do
    it "includes the browser + OS line" do
      expect(template.body).to include("Firefox on Linux")
    end

    it "includes the location line" do
      expect(template.body).to include("Bucharest, RO (Bucharest)")
    end

    it "includes the IP line" do
      expect(template.body).to include("10.0.0.5")
    end

    it "includes the truncated fingerprint" do
      expect(template.body).to include("abcd1234ef56")
    end

    it "includes the two bracketed-link actions" do
      expect(template.body).to include("[yeah, it's me](/login/approvals/42)")
      expect(template.body).to include("[block the intruder](/login/blocks/42)")
    end

    it "renders 'location unknown' when geo_summary is missing" do
      notification.event_payload = notification.event_payload.merge("geo_summary" => nil)
      expect(template.body).to include("location unknown")
    end

    it "renders 'unknown browser' / 'unknown OS' when UA is missing" do
      notification.event_payload = notification.event_payload.merge(
        "browser" => nil, "os" => nil
      )
      expect(template.body).to include("unknown browser on unknown OS")
    end

    it "omits the action line when login_attempt_id is missing" do
      notification.event_payload = notification.event_payload.merge("login_attempt_id" => nil)
      expect(template.body).not_to include("[yeah, it's me]")
      expect(template.body).not_to include("[block the intruder]")
    end
  end

  describe "#url" do
    it "points at the notification detail page" do
      expect(template.url).to eq("/notifications/#{notification.id}")
    end

    it "is nil when the notification has not yet been persisted" do
      unsaved = Notification.new(
        event_type: "login_pending_approval",
        event_payload: {}
      )
      expect(described_class.new(unsaved).url).to be_nil
    end
  end

  describe "registry wiring" do
    it "is registered in NotificationFormatter::Templates::REGISTRY" do
      expect(NotificationFormatter::Templates::REGISTRY["login_pending_approval"])
        .to eq(described_class)
    end

    it "is reachable via NotificationFormatter.template_for" do
      expect(NotificationFormatter.template_for(notification)).to be_a(described_class)
    end
  end
end
