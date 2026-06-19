# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Notifications::Source::VideoSync, type: :service do
  def result(imported: 0, updated: 0, deleted: 0, titles: [])
    Pito::Sync::VideoLibrary::Result.new(imported:, updated:, deleted:, titles:)
  end

  describe ".report!" do
    context "with a noteworthy result" do
      it "creates exactly one Notification" do
        expect {
          described_class.report!(scope_label: "@acme", result: result(imported: 2, titles: [ "A", "B" ]))
        }.to change(Notification, :count).by(1)
      end

      it "includes the scope label and the counts in the message" do
        described_class.report!(
          scope_label: "@acme",
          result: result(imported: 2, updated: 1, deleted: 3, titles: [])
        )
        msg = Notification.last.message
        expect(msg).to include("@acme")
        expect(msg).to include("2")
        expect(msg).to include("1")
        expect(msg).to include("3")
      end

      it "lists a deleted title in the message" do
        described_class.report!(
          scope_label: "@acme",
          result: result(deleted: 1, titles: [ "Old Stream VOD" ])
        )
        expect(Notification.last.message).to include("Old Stream VOD")
      end

      it "returns the created Notification" do
        notification = described_class.report!(scope_label: "@acme", result: result(imported: 1, titles: [ "A" ]))
        expect(notification).to be_a(Notification)
        expect(notification).to be_persisted
      end
    end

    context "with a quiet (zero) result" do
      it "creates no Notification" do
        expect {
          described_class.report!(scope_label: "@acme", result: result)
        }.not_to change(Notification, :count)
      end

      it "returns nil" do
        expect(described_class.report!(scope_label: "@acme", result: result)).to be_nil
      end
    end

    it "HTML-escapes potentially dangerous titles" do
      described_class.report!(
        scope_label: "@acme",
        result: result(deleted: 1, titles: [ "<script>alert('xss')</script>" ])
      )
      msg = Notification.last.message
      expect(msg).not_to include("<script>")
      expect(msg).to include("&lt;script&gt;")
    end

    it "caps the titles list and collapses the overflow into a '+ K more' tail" do
      titles = (1..12).map { |i| "Video #{i}" }
      described_class.report!(scope_label: "@acme", result: result(deleted: 12, titles:))
      msg = Notification.last.message
      expect(msg).to include("Video 10")
      expect(msg).not_to include("Video 11")
      expect(msg).to include("+ 2 more")
    end
  end
end
