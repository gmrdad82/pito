# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelSync, type: :job do
  let(:connection) { create(:youtube_connection) }
  let!(:channel)   { create(:channel, youtube_connection: connection) }
  let(:client)     { instance_double(Channel::Youtube::Client) }
  let(:normalized) { { title: "Synced Channel", handle: "@synced", video_count: 42 } }

  before do
    allow(Channel::Youtube::Client).to receive(:new).with(connection).and_return(client)
    allow(client).to receive(:fetch_channel).and_return(normalized)
  end

  it "updates the channel with the normalized fields from fetch_channel" do
    described_class.perform_now(channel.id)
    expect(channel.reload.title).to eq("Synced Channel")
  end

  it "stamps last_synced_at on success" do
    described_class.perform_now(channel.id)
    expect(channel.reload.last_synced_at).to be_within(5.seconds).of(Time.current)
  end

  it "is a no-op when the channel does not exist" do
    expect { described_class.perform_now(0) }.not_to raise_error
    expect(Channel::Youtube::Client).not_to have_received(:new)
  end

  it "is a no-op when the channel has no youtube_connection" do
    connless = create(:channel, :orphan)
    described_class.perform_now(connless.id)
    expect(Channel::Youtube::Client).not_to have_received(:new)
  end

  it "swallows PermanentError without re-raising" do
    allow(client).to receive(:fetch_channel).and_raise(Channel::Youtube::PermanentError, "deleted")
    expect { described_class.perform_now(channel.id) }.not_to raise_error
  end

  it "does not update the channel on PermanentError" do
    allow(client).to receive(:fetch_channel).and_raise(Channel::Youtube::PermanentError, "deleted")
    expect { described_class.perform_now(channel.id) }.not_to change { channel.reload.last_synced_at }
  end

  it "propagates TransientError so the job framework can retry" do
    allow(client).to receive(:fetch_channel).and_raise(Channel::Youtube::TransientError, "timeout")
    expect { described_class.perform_now(channel.id) }.to raise_error(Channel::Youtube::TransientError)
  end

  context "when the normalized payload includes an avatar URL" do
    before do
      allow(client).to receive(:fetch_channel).and_return(
        normalized.merge(avatar_url: "https://yt3.ggpht.com/avatar.jpg")
      )
    end

    it "enqueues ChannelAvatarJob with the channel id and avatar URL" do
      expect { described_class.perform_now(channel.id) }
        .to have_enqueued_job(ChannelAvatarJob).with(channel.id, "https://yt3.ggpht.com/avatar.jpg")
    end
  end

  context "when the normalized payload includes a banner URL" do
    before do
      allow(client).to receive(:fetch_channel).and_return(
        normalized.merge(banner_url: "https://yt3.ggpht.com/banner")
      )
    end

    it "enqueues ChannelBannerJob with the channel id and banner URL" do
      expect { described_class.perform_now(channel.id) }
        .to have_enqueued_job(ChannelBannerJob).with(channel.id, "https://yt3.ggpht.com/banner")
    end
  end

  it "does not enqueue ChannelAvatarJob when avatar_url is absent" do
    expect { described_class.perform_now(channel.id) }.not_to have_enqueued_job(ChannelAvatarJob)
  end

  it "does not enqueue ChannelBannerJob when banner_url is absent" do
    expect { described_class.perform_now(channel.id) }.not_to have_enqueued_job(ChannelBannerJob)
  end
end
