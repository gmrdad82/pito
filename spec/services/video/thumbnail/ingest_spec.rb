# frozen_string_literal: true

require "rails_helper"

RSpec.describe Video::Thumbnail::Ingest do
  let(:channel)   { create(:channel) }
  let(:video)     { create(:video, channel:) }
  # Raw bytes that stand in for a real YouTube thumbnail — not resized/processed.
  let(:raw_bytes) { "fake-thumbnail-raw-bytes-v1" }

  # Stub the thumbnail source URL as a successful HTTP response.
  def stub_thumbnail_fetch(url: "https://i.ytimg.com/vi/abc123/maxresdefault.jpg",
                           body: raw_bytes, status: 200)
    stub_request(:get, url).to_return(
      status:  status,
      body:    body,
      headers: { "Content-Type" => "image/jpeg" }
    )
  end

  it "attaches the raw (unprocessed) thumbnail bytes as the master blob" do
    stub_thumbnail_fetch
    described_class.new(video:, source_url: "https://i.ytimg.com/vi/abc123/maxresdefault.jpg").call
    expect(video.thumbnail).to be_attached
    expect(video.thumbnail.blob.content_type).to eq("image/jpeg")
  end

  it "does NOT run Pito::Image::Normalizer (no resize before attach)" do
    stub_thumbnail_fetch
    expect(Pito::Image::Normalizer).not_to receive(:new)
    described_class.new(video:, source_url: "https://i.ytimg.com/vi/abc123/maxresdefault.jpg").call
  end

  it "uses a video-unique filename (thumbnail-<id>.jpg)" do
    stub_thumbnail_fetch
    described_class.new(video:, source_url: "https://i.ytimg.com/vi/abc123/maxresdefault.jpg").call
    expect(video.thumbnail.blob.filename.to_s).to eq("thumbnail-#{video.id}.jpg")
  end

  it "no-ops on a blank source URL" do
    described_class.new(video:, source_url: nil).call
    expect(video.thumbnail).not_to be_attached
  end

  # Digest-gate: re-attach ONLY when the raw source bytes change.
  it "does NOT re-attach when a sync returns the identical thumbnail bytes (digest-gate)" do
    stub_thumbnail_fetch
    described_class.new(video:, source_url: "https://i.ytimg.com/vi/abc123/maxresdefault.jpg").call
    first_blob_id = video.thumbnail.blob.id

    described_class.new(video: video.reload, source_url: "https://i.ytimg.com/vi/abc123/maxresdefault.jpg").call
    expect(video.reload.thumbnail.blob.id).to eq(first_blob_id)
  end

  it "re-attaches when the thumbnail bytes change" do
    stub_thumbnail_fetch
    described_class.new(video:, source_url: "https://i.ytimg.com/vi/abc123/maxresdefault.jpg").call
    first_blob_id = video.thumbnail.blob.id

    stub_request(:get, "https://i.ytimg.com/vi/abc123/maxresdefault.jpg")
      .to_return(status: 200, body: "fake-thumbnail-raw-bytes-v2", headers: { "Content-Type" => "image/jpeg" })
    described_class.new(video: video.reload, source_url: "https://i.ytimg.com/vi/abc123/maxresdefault.jpg").call
    expect(video.reload.thumbnail.blob.id).not_to eq(first_blob_id)
  end

  it "swallows a fetch failure and leaves no attachment" do
    stub_request(:get, "https://i.ytimg.com/vi/abc123/maxresdefault.jpg")
      .to_return(status: 429, body: "", headers: {})
    expect {
      described_class.new(video:, source_url: "https://i.ytimg.com/vi/abc123/maxresdefault.jpg").call
    }.not_to raise_error
    expect(video.thumbnail).not_to be_attached
  end
end
