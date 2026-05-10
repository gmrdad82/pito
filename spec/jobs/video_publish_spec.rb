require "rails_helper"

RSpec.describe VideoPublish, type: :job do
  let(:user) { User.first || create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) { create(:channel, youtube_connection: connection) }

  it "no-ops when video is missing" do
    expect { described_class.new.perform(99999, "public") }.not_to raise_error
  end

  it "no-ops when pre_publish is incomplete" do
    v = create(:video, channel: channel) # NOT pre_publish_complete
    described_class.new.perform(v.id, "public")
    expect(v.reload.privacy_private?).to be(true)
  end

  it "publishes a complete video" do
    v = create(:video, :pre_publish_complete, channel: channel,
                       title: "ok", category_id: "20")
    VideoSyncBack.jobs.clear
    described_class.new.perform(v.id, "public")
    expect(v.reload.privacy_public?).to be(true)
  end

  it "schedules with publish_at" do
    v = create(:video, :pre_publish_complete, channel: channel,
                       title: "ok", category_id: "20")
    future = 1.day.from_now
    described_class.new.perform(v.id, "scheduled", future.iso8601)
    v.reload
    expect(v.privacy_private?).to be(true)
    expect(v.publish_at).to be_within(2.seconds).of(future)
  end

  it "configures sidekiq retry to 3" do
    expect(described_class.sidekiq_options["retry"]).to eq(3)
  end
end
