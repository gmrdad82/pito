# frozen_string_literal: true

require "rails_helper"

RSpec.describe VideoRemoteStatusSync, type: :job do
  let(:connection) { create(:youtube_connection) }
  let!(:channel)   { create(:channel, youtube_connection: connection) }
  let!(:video)     { create(:video, channel: channel, privacy_status: :public) }

  let(:reader) { instance_double(Channel::Youtube::VideosReader) }
  let(:client) { instance_double(Channel::Youtube::VideosClient) }
  let(:fresh)  { { snippet: { title: "remote" }, status: { privacyStatus: "private" } } }

  before do
    allow(Channel::Youtube::VideosReader).to receive(:new).with(connection).and_return(reader)
    allow(Channel::Youtube::VideosClient).to receive(:new).with(connection).and_return(client)
    allow(reader).to receive(:read_video).with(video).and_return(fresh)
    allow(client).to receive(:update_video)
  end

  it "overlays ONLY privacy_status and publish_at on the fresh snapshot" do
    described_class.perform_now(video.id)
    expect(client).to have_received(:update_video).with(
      video, fresh: fresh, fields: [ :privacy_status, :publish_at ]
    )
  end

  it "stamps last_synced_at on success" do
    described_class.perform_now(video.id)
    expect(video.reload.last_synced_at).to be_within(5.seconds).of(Time.current)
  end

  it "is a no-op when the video does not exist" do
    expect { described_class.perform_now(0) }.not_to raise_error
    expect(Channel::Youtube::VideosClient).not_to have_received(:new)
  end

  it "is a no-op when the connection is missing" do
    connless = create(:video, channel: create(:channel, :orphan))
    described_class.perform_now(connless.id)
    expect(Channel::Youtube::VideosClient).not_to have_received(:new)
  end

  it "is a no-op when the connection needs reauth" do
    connection.update!(needs_reauth: true)
    described_class.perform_now(video.id)
    expect(Channel::Youtube::VideosClient).not_to have_received(:new)
  end

  it "surfaces the reauth reminder when the connection needs reauth (not silent)" do
    connection.update!(needs_reauth: true)
    expect { described_class.perform_now(video.id) }.to change(Notification, :count).by(1)
    expect(Notification.last.message).to include("re-auth needed")
  end

  it "does not duplicate the reauth reminder while one is unread (dedup)" do
    connection.update!(needs_reauth: true)
    described_class.perform_now(video.id)
    expect { described_class.perform_now(video.id) }.not_to change(Notification, :count)
  end

  it "re-raises on quota exhaustion" do
    allow(reader).to receive(:read_video).and_raise(Channel::Youtube::QuotaExhaustedError, "quota")
    expect { described_class.perform_now(video.id) }.to raise_error(Channel::Youtube::QuotaExhaustedError)
  end

  it "marks the connection needs_reauth on AuthRevokedError without re-raising" do
    allow(reader).to receive(:read_video).and_raise(Channel::Youtube::AuthRevokedError, "revoked")
    expect { described_class.perform_now(video.id) }.not_to raise_error
    expect(connection.reload.needs_reauth).to be(true)
  end

  it "swallows ValidationError (non-retriable)" do
    allow(client).to receive(:update_video).and_raise(Channel::Youtube::ValidationError, "bad")
    expect { described_class.perform_now(video.id) }.not_to raise_error
  end

  it "surfaces a Notification when YouTube rejects the update (ValidationError)" do
    allow(client).to receive(:update_video).and_raise(Channel::Youtube::ValidationError, "invalidPublishAt")
    expect { described_class.perform_now(video.id) }.to change(Notification, :count).by(1)
    expect(Notification.last.message).to include(video.title)
    expect(Notification.last.level).to eq("error")
  end

  it "surfaces a Notification when the video is not found on YouTube (NotFoundError)" do
    allow(client).to receive(:update_video).and_raise(Channel::Youtube::NotFoundError, "gone")
    expect { described_class.perform_now(video.id) }.to change(Notification, :count).by(1)
  end

  it "surfaces a reauth Notification on AuthRevokedError (no longer silent)" do
    allow(reader).to receive(:read_video).and_raise(Channel::Youtube::AuthRevokedError, "revoked")
    expect { described_class.perform_now(video.id) }.to change(Notification, :count).by(1)
    expect(Notification.last.message).to include("re-auth needed")
  end

  it "includes the video title in the Notification message on NotFoundError" do
    allow(client).to receive(:update_video).and_raise(Channel::Youtube::NotFoundError, "gone")
    described_class.perform_now(video.id)
    expect(Notification.last.message).to include(video.title)
  end

  it "does not stamp last_synced_at on ValidationError" do
    allow(client).to receive(:update_video).and_raise(Channel::Youtube::ValidationError, "bad")
    expect {
      described_class.perform_now(video.id)
    }.not_to change { video.reload.last_synced_at }
  end

  it "does not stamp last_synced_at on AuthRevokedError" do
    allow(reader).to receive(:read_video).and_raise(Channel::Youtube::AuthRevokedError, "revoked")
    expect {
      described_class.perform_now(video.id)
    }.not_to change { video.reload.last_synced_at }
  end

  it "re-raises on ServerError" do
    allow(client).to receive(:update_video).and_raise(Channel::Youtube::ServerError, "boom")
    expect { described_class.perform_now(video.id) }.to raise_error(Channel::Youtube::ServerError)
  end
end
