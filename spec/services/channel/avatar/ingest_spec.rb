# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::Avatar::Ingest do
  let(:channel) { create(:channel) }
  let(:jpeg_bytes) { Vips::Image.black(240, 240).cast(:uchar).bandjoin([ 0, 0 ]).jpegsave_buffer }

  it "attaches a normalized avatar from the source URL" do
    allow_any_instance_of(Pito::Image::Normalizer).to receive(:call).and_return(jpeg_bytes)

    described_class.new(channel:, source_url: "https://yt3.ggpht.com/x=s800").call

    expect(channel.avatar).to be_attached
    expect(channel.avatar.blob.content_type).to eq("image/jpeg")
  end

  it "no-ops on a blank source URL" do
    described_class.new(channel:, source_url: nil).call
    expect(channel.avatar).not_to be_attached
  end

  it "swallows a fetch failure and leaves no attachment" do
    allow_any_instance_of(Pito::Image::Normalizer)
      .to receive(:call)
      .and_raise(Pito::Error::ExternalFetchFailed.new(source: "YouTube CDN", http_code: "429", detail: "x"))

    expect {
      described_class.new(channel:, source_url: "https://yt3.ggpht.com/x").call
    }.not_to raise_error
    expect(channel.avatar).not_to be_attached
  end
end
