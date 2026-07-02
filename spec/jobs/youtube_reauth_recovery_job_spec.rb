# frozen_string_literal: true

require "rails_helper"

RSpec.describe YoutubeReauthRecoveryJob, type: :job do
  include ActiveJob::TestHelper

  let!(:connection) { create(:youtube_connection, needs_reauth: false) }
  let!(:channel)    { create(:channel, youtube_connection: connection) }
  let!(:channel2)   { create(:channel, youtube_connection: connection) }

  before { allow(Pito::Jobs::RequeueFailed).to receive(:call).and_return(0) }

  it "requeues ALL failed executions (owner: all, not just auth-classed)" do
    described_class.perform_now(connection.id)

    expect(Pito::Jobs::RequeueFailed).to have_received(:call).with(target: "all")
  end

  it "fans out the skipped nightly pair per channel + the global stats/achievements passes" do
    described_class.perform_now(connection.id)

    [ channel, channel2 ].each do |ch|
      expect(ChannelSync).to have_been_enqueued.with(ch.id)
      expect(VideoSyncJob).to have_been_enqueued.with(ch.id)
    end
    expect(VideoStatsSnapshotJob).to have_been_enqueued
    expect(AchievementsRefreshJob).to have_been_enqueued
  end

  it "creates NO notification (the reauth notice already exists — owner)" do
    expect { described_class.perform_now(connection.id) }
      .not_to change(Notification, :count)
  end

  it "no-ops when the connection was re-flagged before the job ran" do
    connection.update_columns(needs_reauth: true)

    described_class.perform_now(connection.id)

    expect(Pito::Jobs::RequeueFailed).not_to have_received(:call)
    expect(ChannelSync).not_to have_been_enqueued
  end

  it "no-ops when the connection no longer exists" do
    expect { described_class.perform_now(0) }.not_to raise_error
    expect(Pito::Jobs::RequeueFailed).not_to have_received(:call)
  end
end
