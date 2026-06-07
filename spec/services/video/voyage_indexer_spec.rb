# frozen_string_literal: true

require "rails_helper"

RSpec.describe Video::VoyageIndexer, type: :service do
  let(:video) do
    create(:video, title: "Lies of P — Boss Guide", description: "Every boss.", tags: %w[soulslike], category_id: "20")
  end
  let(:client) { instance_double(Voyage::Client) }

  before do
    AppSetting.singleton_row.update!(voyage_api_key: "test-key")
    allow(Voyage::Client).to receive(:new).and_return(client)
    allow(client).to receive(:embed).and_return([ Array.new(1024, 0.1) ])
  end

  it "embeds and stores the digest on first index" do
    expect { described_class.call(video) }.to change { video.reload.embedded_digest }.from(nil)
    expect(video.summary_embedding).to be_present
  end

  it "no-ops when the indexed text is unchanged" do
    described_class.call(video)
    expect(client).not_to receive(:embed)
    described_class.call(video.reload)
  end

  it "re-embeds when an indexed field changes" do
    described_class.call(video)
    video.update_column(:description, "A different focus.")
    expect(client).to receive(:embed).and_return([ Array.new(1024, 0.2) ])
    described_class.call(video.reload)
  end

  it "force: re-embeds even when the digest is unchanged" do
    described_class.call(video)
    expect(client).to receive(:embed).and_return([ Array.new(1024, 0.3) ])
    described_class.call(video.reload, force: true)
  end

  it "no-ops when Voyage is not configured" do
    AppSetting.singleton_row.update!(voyage_api_key: nil)
    expect(client).not_to receive(:embed)
    described_class.call(video)
  end

  it "raises Pito::Error::VoyageEmbeddingNil when embed returns [nil]" do
    allow(client).to receive(:embed).and_return([ nil ])
    expect { described_class.call(video) }.to raise_error(Pito::Error::VoyageEmbeddingNil)
  end
end
