# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Notifications::Source::YoutubeReauth do
  describe ".report!" do
    let(:connection) { create(:youtube_connection, email: "owner@example.com") }
    let!(:channel) { create(:channel, youtube_connection: connection, handle: "alpha") }

    it "creates a notification naming the connection's channels" do
      expect { described_class.report!(connection) }.to change(Notification, :count).by(1)
      expect(Notification.last.message).to include("alpha")
      expect(Notification.last.message).to include("reconnect via /connect")
      expect(Notification.last.level).to eq("warning")
    end

    it "falls back to the connection email when it has no channels" do
      channel.update!(youtube_connection: nil)
      described_class.report!(connection.reload)
      expect(Notification.last.message).to include("owner@example.com")
    end

    it "does not create a duplicate while an identical reminder is unread" do
      described_class.report!(connection)
      expect { described_class.report!(connection) }.not_to change(Notification, :count)
    end

    it "creates a fresh reminder once the prior one has been read" do
      first = described_class.report!(connection)
      first.update!(read_at: Time.current)
      expect { described_class.report!(connection) }.to change(Notification, :count).by(1)
    end

    it "returns nil for a nil connection" do
      expect(described_class.report!(nil)).to be_nil
    end
  end
end
