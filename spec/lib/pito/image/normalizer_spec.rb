# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Image::Normalizer do
  # A real 400x300 JPEG so libvips has valid bytes to crop/resize.
  let(:source_bytes) { Vips::Image.black(400, 300).cast(:uchar).bandjoin([ 0, 0 ]).jpegsave_buffer }
  let(:url) { "https://yt3.ggpht.com/test-avatar=s800" }

  it "fetches the URL and returns a JPEG normalized to exactly WxH" do
    stub_request(:get, url).to_return(status: 200, body: source_bytes, headers: { "Content-Type" => "image/jpeg" })

    out = described_class.new(url: url, width: 240, height: 240).call
    img = Vips::Image.new_from_buffer(out, "")

    expect(img.width).to eq(240)
    expect(img.height).to eq(240)
  end

  it "follows a redirect to the final image" do
    final = "https://cdn.example.com/real.jpg"
    stub_request(:get, url).to_return(status: 302, headers: { "Location" => final })
    stub_request(:get, final).to_return(status: 200, body: source_bytes, headers: { "Content-Type" => "image/jpeg" })

    out = described_class.new(url: url, width: 100, height: 100).call
    expect(Vips::Image.new_from_buffer(out, "").width).to eq(100)
  end

  it "raises ExternalFetchFailed on a non-2xx terminal response" do
    stub_request(:get, url).to_return(status: 429)

    expect {
      described_class.new(url: url, width: 240, height: 240).call
    }.to raise_error(Pito::Error::ExternalFetchFailed)
  end
end
