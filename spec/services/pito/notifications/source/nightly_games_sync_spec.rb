# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Notifications::Source::NightlyGamesSync, type: :service do
  describe ".report!" do
    it "creates exactly one Notification" do
      expect {
        described_class.report!(checked: 3, updated: 1, changed_titles: [ "Game A" ], failures: [])
      }.to change(Notification, :count).by(1)
    end

    it "returns the created Notification" do
      result = described_class.report!(checked: 5, updated: 2, changed_titles: [ "A", "B" ], failures: [])
      expect(result).to be_a(Notification)
      expect(result).to be_persisted
    end

    context "with no failures" do
      it "includes the checked and updated counts in the message" do
        described_class.report!(checked: 4, updated: 2, changed_titles: [ "Alpha", "Beta" ], failures: [])
        msg = Notification.last.message
        expect(msg).to include("4")
        expect(msg).to include("2")
      end

      it "includes changed game titles in the message" do
        described_class.report!(checked: 1, updated: 1, changed_titles: [ "Hollow Knight" ], failures: [])
        expect(Notification.last.message).to include("Hollow Knight")
      end

      it "does not include failure content when there are no failures" do
        described_class.report!(checked: 2, updated: 0, changed_titles: [], failures: [])
        expect(Notification.last.message).not_to include("failed to sync")
      end
    end

    context "with failures" do
      let(:failures) { [ { title: "Broken Game", error: "RuntimeError: IGDB exploded" } ] }

      it "includes the failure count in the message" do
        described_class.report!(checked: 3, updated: 0, changed_titles: [], failures: failures)
        expect(Notification.last.message).to include("1")
      end

      it "includes the failing game title in the message" do
        described_class.report!(checked: 3, updated: 0, changed_titles: [], failures: failures)
        expect(Notification.last.message).to include("Broken Game")
      end

      it "includes the error text in the message" do
        described_class.report!(checked: 3, updated: 0, changed_titles: [], failures: failures)
        expect(Notification.last.message).to include("IGDB exploded")
      end
    end

    context "with zero games" do
      it "still creates a Notification" do
        expect {
          described_class.report!(checked: 0, updated: 0, changed_titles: [], failures: [])
        }.to change(Notification, :count).by(1)
      end

      it "message includes zero counts" do
        described_class.report!(checked: 0, updated: 0, changed_titles: [], failures: [])
        msg = Notification.last.message
        expect(msg).to include("0")
      end
    end

    it "HTML-escapes potentially dangerous game titles" do
      described_class.report!(checked: 1, updated: 1,
                               changed_titles: [ "<script>alert('xss')</script>" ],
                               failures: [])
      msg = Notification.last.message
      expect(msg).not_to include("<script>")
      expect(msg).to include("&lt;script&gt;")
    end
  end
end
