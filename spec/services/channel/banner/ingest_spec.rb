# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::Banner::Ingest do
  let(:channel) { create(:channel) }
  let(:jpeg_bytes) { Vips::Image.black(374, 210).cast(:uchar).bandjoin([ 0, 0 ]).jpegsave_buffer }

  it "attaches a normalized 374x210 banner from the source URL" do
    allow_any_instance_of(Pito::Image::Normalizer).to receive(:call).and_return(jpeg_bytes)

    described_class.new(channel:, source_url: "https://yt3.ggpht.com/banner").call

    expect(channel.banner).to be_attached
    expect(channel.banner.blob.content_type).to eq("image/jpeg")
  end

  it "requests the ORIGINAL banner (=w2560-h1440) and normalizes to the vid-thumbnail box (374x210, 16:9)" do
    # The raw bannerExternalUrl serves only a small 512x288 default; the size
    # suffix fetches the original 2560x1440 (16:9), downscaled to 374x210 — clean,
    # no crop, since both are 16:9.
    normalizer = instance_double(Pito::Image::Normalizer, call: jpeg_bytes)
    expect(Pito::Image::Normalizer).to receive(:new)
      .with(url: "https://yt3.googleusercontent.com/TOKEN=w2560-h1440", width: 374, height: 210).and_return(normalizer)

    described_class.new(channel:, source_url: "https://yt3.googleusercontent.com/TOKEN").call
  end

  it "uses a channel-unique filename (banner-<id>.jpg)" do
    allow_any_instance_of(Pito::Image::Normalizer).to receive(:call).and_return(jpeg_bytes)
    described_class.new(channel:, source_url: "https://yt3.ggpht.com/banner").call
    expect(channel.banner.blob.filename.to_s).to eq("banner-#{channel.id}.jpg")
  end

  it "no-ops on a blank source URL" do
    described_class.new(channel:, source_url: nil).call
    expect(channel.banner).not_to be_attached
  end

  it "swallows a fetch failure and leaves no attachment" do
    allow_any_instance_of(Pito::Image::Normalizer)
      .to receive(:call)
      .and_raise(Pito::Error::ExternalFetchFailed.new(source: "YouTube CDN", http_code: "429", detail: "x"))

    expect {
      described_class.new(channel:, source_url: "https://yt3.ggpht.com/banner").call
    }.not_to raise_error
    expect(channel.banner).not_to be_attached
  end
end
