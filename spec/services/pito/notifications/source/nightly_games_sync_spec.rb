# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Notifications::Source::NightlyGamesSync, type: :service do
  describe ".report!" do
    it "creates exactly one Notification" do
      expect {
        described_class.report!(checked: 3, changed: [ "Game A" ], failures: [], releasing_30d: [])
      }.to change(Notification, :count).by(1)
    end

    it "returns the created Notification" do
      result = described_class.report!(checked: 5, changed: [ "A", "B" ], failures: [], releasing_30d: [])
      expect(result).to be_a(Notification)
      expect(result).to be_persisted
    end

    context "with no failures and no releasing_30d" do
      it "includes the checked and updated counts in the message" do
        described_class.report!(checked: 4, changed: [ "Alpha", "Beta" ], failures: [], releasing_30d: [])
        msg = Notification.last.message
        expect(msg).to include("4")
        expect(msg).to include("2")
      end

      it "includes changed game titles in the message" do
        described_class.report!(checked: 1, changed: [ "Hollow Knight" ], failures: [], releasing_30d: [])
        expect(Notification.last.message).to include("Hollow Knight")
      end

      it "does not include failure content when there are no failures" do
        described_class.report!(checked: 2, changed: [], failures: [], releasing_30d: [])
        expect(Notification.last.message).not_to include("failed to sync")
      end
    end

    context "with failures" do
      let(:failures) { [ { title: "Broken Game", error: "RuntimeError: IGDB exploded" } ] }

      it "includes the failure count in the message" do
        described_class.report!(checked: 3, changed: [], failures: failures, releasing_30d: [])
        expect(Notification.last.message).to include("1")
      end

      it "includes the failing game title in the message" do
        described_class.report!(checked: 3, changed: [], failures: failures, releasing_30d: [])
        expect(Notification.last.message).to include("Broken Game")
      end

      it "includes the error text in the message" do
        described_class.report!(checked: 3, changed: [], failures: failures, releasing_30d: [])
        expect(Notification.last.message).to include("IGDB exploded")
      end
    end

    context "with releasing_30d games" do
      let(:soon_date) { Date.current + 15.days }
      let(:releasing_30d) { [ { title: "Soon Game", release_date: soon_date } ] }

      it "includes the releasing soon header in the message" do
        described_class.report!(checked: 2, changed: [], failures: [], releasing_30d: releasing_30d)
        expect(Notification.last.message).to include("30 days")
      end

      it "includes the releasing game title in the message" do
        described_class.report!(checked: 2, changed: [], failures: [], releasing_30d: releasing_30d)
        expect(Notification.last.message).to include("Soon Game")
      end

      it "includes the release date in the message" do
        described_class.report!(checked: 2, changed: [], failures: [], releasing_30d: releasing_30d)
        expect(Notification.last.message).to include(soon_date.to_s)
      end
    end

    it "HTML-escapes potentially dangerous game titles in changed list" do
      described_class.report!(checked: 1,
                               changed: [ "<script>alert('xss')</script>" ],
                               failures: [],
                               releasing_30d: [])
      msg = Notification.last.message
      expect(msg).not_to include("<script>")
      expect(msg).to include("&lt;script&gt;")
    end

    it "HTML-escapes potentially dangerous game titles in releasing_30d list" do
      described_class.report!(checked: 1,
                               changed: [],
                               failures: [],
                               releasing_30d: [ { title: "<script>xss</script>", release_date: Date.current + 5.days } ])
      msg = Notification.last.message
      expect(msg).not_to include("<script>xss</script>")
      expect(msg).to include("&lt;script&gt;")
    end
  end
end
