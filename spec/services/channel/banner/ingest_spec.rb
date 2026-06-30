# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::Banner::Ingest do
  let(:channel)   { create(:channel) }
  # Raw bytes that stand in for a real YouTube banner master — not resized/processed.
  let(:raw_bytes) { "fake-banner-raw-bytes-v1" }

  # Stub the full-res banner URL (=w2560-h1440) as a successful HTTP response.
  def stub_banner_fetch(url: "https://yt3.googleusercontent.com/TOKEN=w2560-h1440",
                        body: raw_bytes, status: 200)
    stub_request(:get, url).to_return(
      status:  status,
      body:    body,
      headers: { "Content-Type" => "image/jpeg" }
    )
  end

  it "attaches the raw (unprocessed) banner bytes as the master blob" do
    stub_banner_fetch
    described_class.new(channel:, source_url: "https://yt3.googleusercontent.com/TOKEN").call
    expect(channel.banner).to be_attached
    expect(channel.banner.blob.content_type).to eq("image/jpeg")
  end

  it "requests the ORIGINAL banner URL (=w2560-h1440 suffix)" do
    stub_banner_fetch
    described_class.new(channel:, source_url: "https://yt3.googleusercontent.com/TOKEN").call
    expect(WebMock).to have_requested(:get, "https://yt3.googleusercontent.com/TOKEN=w2560-h1440")
  end

  it "does NOT run Pito::Image::Normalizer (no resize before attach)" do
    stub_banner_fetch
    expect(Pito::Image::Normalizer).not_to receive(:new)
    described_class.new(channel:, source_url: "https://yt3.googleusercontent.com/TOKEN").call
  end

  it "uses a channel-unique filename (banner-<id>.jpg)" do
    stub_banner_fetch
    described_class.new(channel:, source_url: "https://yt3.googleusercontent.com/TOKEN").call
    expect(channel.banner.blob.filename.to_s).to eq("banner-#{channel.id}.jpg")
  end

  it "replaces a pre-existing suffix on the source URL rather than doubling it" do
    stub_request(:get, "https://yt3.googleusercontent.com/TOKEN=w2560-h1440")
      .to_return(status: 200, body: raw_bytes, headers: { "Content-Type" => "image/jpeg" })
    described_class.new(channel:, source_url: "https://yt3.googleusercontent.com/TOKEN=s800").call
    expect(WebMock).to have_requested(:get, "https://yt3.googleusercontent.com/TOKEN=w2560-h1440")
  end

  it "no-ops on a blank source URL" do
    described_class.new(channel:, source_url: nil).call
    expect(channel.banner).not_to be_attached
  end

  # Digest-gate: re-attach ONLY when the raw source bytes change.
  it "does NOT re-attach when a sync returns the identical banner bytes (digest-gate)" do
    stub_banner_fetch
    described_class.new(channel:, source_url: "https://yt3.googleusercontent.com/TOKEN").call
    first_blob_id = channel.banner.blob.id

    described_class.new(channel: channel.reload, source_url: "https://yt3.googleusercontent.com/TOKEN").call
    expect(channel.reload.banner.blob.id).to eq(first_blob_id)
  end

  it "re-attaches when the banner bytes change" do
    stub_banner_fetch
    described_class.new(channel:, source_url: "https://yt3.googleusercontent.com/TOKEN").call
    first_blob_id = channel.banner.blob.id

    stub_request(:get, "https://yt3.googleusercontent.com/TOKEN=w2560-h1440")
      .to_return(status: 200, body: "fake-banner-raw-bytes-v2", headers: { "Content-Type" => "image/jpeg" })
    described_class.new(channel: channel.reload, source_url: "https://yt3.googleusercontent.com/TOKEN").call
    expect(channel.reload.banner.blob.id).not_to eq(first_blob_id)
  end

  it "swallows a fetch failure and leaves no attachment" do
    stub_request(:get, "https://yt3.googleusercontent.com/TOKEN=w2560-h1440")
      .to_return(status: 429, body: "", headers: {})
    expect {
      described_class.new(channel:, source_url: "https://yt3.googleusercontent.com/TOKEN").call
    }.not_to raise_error
    expect(channel.banner).not_to be_attached
  end
end
