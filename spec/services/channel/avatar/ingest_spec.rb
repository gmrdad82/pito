# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::Avatar::Ingest do
  let(:channel)   { create(:channel) }
  # Raw bytes that stand in for a real YouTube avatar master — not resized/processed.
  let(:raw_bytes) { "fake-avatar-raw-bytes-v1" }

  # Stub a successful HTTP avatar fetch.
  def stub_avatar_fetch(url: "https://yt3.ggpht.com/x=s800",
                        body: raw_bytes, status: 200)
    stub_request(:get, url).to_return(
      status:  status,
      body:    body,
      headers: { "Content-Type" => "image/jpeg" }
    )
  end

  it "attaches the raw (unprocessed) avatar bytes as the master blob" do
    stub_avatar_fetch
    described_class.new(channel:, source_url: "https://yt3.ggpht.com/x=s800").call
    expect(channel.avatar).to be_attached
    expect(channel.avatar.blob.content_type).to eq("image/jpeg")
  end

  it "does NOT run Pito::Image::Normalizer (no resize before attach)" do
    stub_avatar_fetch
    expect(Pito::Image::Normalizer).not_to receive(:new)
    described_class.new(channel:, source_url: "https://yt3.ggpht.com/x=s800").call
  end

  it "uses a channel-unique filename (avatar-<id>.jpg) to harden the proxy URL tail against CDN cache collisions" do
    stub_avatar_fetch
    described_class.new(channel:, source_url: "https://yt3.ggpht.com/x=s800").call
    expect(channel.avatar.blob.filename.to_s).to eq("avatar-#{channel.id}.jpg")
  end

  it "no-ops on a blank source URL" do
    described_class.new(channel:, source_url: nil).call
    expect(channel.avatar).not_to be_attached
  end

  # Digest-gate: re-attach ONLY when the raw source bytes change.
  it "does NOT re-attach when a sync returns the identical avatar bytes (digest-gate)" do
    stub_avatar_fetch
    described_class.new(channel:, source_url: "https://yt3.ggpht.com/x=s800").call
    first_blob_id = channel.avatar.blob.id

    described_class.new(channel: channel.reload, source_url: "https://yt3.ggpht.com/x=s800").call
    expect(channel.reload.avatar.blob.id).to eq(first_blob_id)
  end

  it "re-attaches when the avatar bytes change" do
    stub_avatar_fetch
    described_class.new(channel:, source_url: "https://yt3.ggpht.com/x=s800").call
    first_blob_id = channel.avatar.blob.id

    stub_request(:get, "https://yt3.ggpht.com/x=s800")
      .to_return(status: 200, body: "fake-avatar-raw-bytes-v2", headers: { "Content-Type" => "image/jpeg" })
    described_class.new(channel: channel.reload, source_url: "https://yt3.ggpht.com/x=s800").call
    expect(channel.reload.avatar.blob.id).not_to eq(first_blob_id)
  end

  it "swallows a fetch failure and leaves no attachment" do
    stub_request(:get, "https://yt3.ggpht.com/x").to_return(status: 429, body: "", headers: {})
    expect {
      described_class.new(channel:, source_url: "https://yt3.ggpht.com/x").call
    }.not_to raise_error
    expect(channel.avatar).not_to be_attached
  end
end
