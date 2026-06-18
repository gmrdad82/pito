# frozen_string_literal: true

require "rails_helper"

RSpec.describe YoutubeReauthCheckJob, type: :job do
  subject(:job) { described_class.new }

  describe "#perform" do
    it "creates one Notification for a connection that needs reauth" do
      create(:youtube_connection, :needs_reauth)

      expect { job.perform }.to change(Notification, :count).by(1)
    end

    it "does not create a Notification for a healthy connection" do
      create(:youtube_connection)

      expect { job.perform }.not_to change(Notification, :count)
    end

    it "is idempotent — running twice does not duplicate while the reminder is unread" do
      create(:youtube_connection, :needs_reauth)

      job.perform
      expect { job.perform }.not_to change(Notification, :count)
    end

    it "writes a reconnect reminder message" do
      create(:youtube_connection, :needs_reauth)

      job.perform
      expect(Notification.last.message).to include("re-auth needed")
      expect(Notification.last.message).to include("reconnect")
    end
  end
end
