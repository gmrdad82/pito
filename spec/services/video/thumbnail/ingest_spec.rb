# frozen_string_literal: true

require "rails_helper"

RSpec.describe Video::Thumbnail::Ingest do
  let(:channel) { create(:channel) }
  let(:video)   { create(:video, channel:) }
  let(:jpeg_bytes) { Vips::Image.black(480, 270).cast(:uchar).bandjoin([ 0, 0 ]).jpegsave_buffer }

  it "attaches a normalized thumbnail from the source URL" do
    allow_any_instance_of(Pito::Image::Normalizer).to receive(:call).and_return(jpeg_bytes)

    described_class.new(video:, source_url: "https://i.ytimg.com/vi/x/hqdefault.jpg").call

    expect(video.thumbnail).to be_attached
    expect(video.thumbnail.blob.content_type).to eq("image/jpeg")
  end

  it "no-ops on a blank source URL" do
    described_class.new(video:, source_url: nil).call
    expect(video.thumbnail).not_to be_attached
  end

  it "swallows a fetch failure and leaves no attachment" do
    allow_any_instance_of(Pito::Image::Normalizer)
      .to receive(:call)
      .and_raise(Pito::Error::ExternalFetchFailed.new(source: "YouTube CDN", http_code: "429", detail: "x"))

    expect {
      described_class.new(video:, source_url: "https://i.ytimg.com/vi/x/hqdefault.jpg").call
    }.not_to raise_error
    expect(video.thumbnail).not_to be_attached
  end
end
