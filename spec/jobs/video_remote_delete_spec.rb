# frozen_string_literal: true

require "rails_helper"

RSpec.describe VideoRemoteDelete, type: :job do
  let(:connection) { create(:youtube_connection) }
  let(:yt_id)      { "yt_video_remote_delete" }

  let(:client) { instance_double(Channel::Youtube::VideosClient) }

  before do
    allow(Channel::Youtube::VideosClient).to receive(:new).with(connection).and_return(client)
    allow(client).to receive(:delete_video)
  end

  it "calls delete_video with a struct carrying the youtube id" do
    described_class.perform_now(yt_id, connection.id)
    expect(client).to have_received(:delete_video) do |video|
      expect(video.youtube_video_id).to eq(yt_id)
    end
  end

  it "is a no-op when the youtube id is blank" do
    described_class.perform_now("", connection.id)
    expect(Channel::Youtube::VideosClient).not_to have_received(:new)
  end

  it "is a no-op when the connection is missing" do
    described_class.perform_now(yt_id, 0)
    expect(Channel::Youtube::VideosClient).not_to have_received(:new)
  end

  it "is a no-op when the connection needs reauth" do
    connection.update!(needs_reauth: true)
    described_class.perform_now(yt_id, connection.id)
    expect(Channel::Youtube::VideosClient).not_to have_received(:new)
  end

  it "surfaces the reauth reminder when the connection needs reauth (not silent)" do
    connection.update!(needs_reauth: true)
    expect { described_class.perform_now(yt_id, connection.id) }.to change(Notification, :count).by(1)
    expect(Notification.last.message).to include("re-auth needed")
  end

  it "re-raises on quota exhaustion" do
    allow(client).to receive(:delete_video).and_raise(Channel::Youtube::QuotaExhaustedError, "quota")
    expect { described_class.perform_now(yt_id, connection.id) }.to raise_error(Channel::Youtube::QuotaExhaustedError)
  end

  it "marks the connection needs_reauth on AuthRevokedError without re-raising" do
    allow(client).to receive(:delete_video).and_raise(Channel::Youtube::AuthRevokedError, "revoked")
    expect { described_class.perform_now(yt_id, connection.id) }.not_to raise_error
    expect(connection.reload.needs_reauth).to be(true)
  end

  it "swallows NotFoundError (already gone on YouTube)" do
    allow(client).to receive(:delete_video).and_raise(Channel::Youtube::NotFoundError, "gone")
    expect { described_class.perform_now(yt_id, connection.id) }.not_to raise_error
  end
end
