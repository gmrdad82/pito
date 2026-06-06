# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::VoyageIndexer, type: :service do
  let(:channel) do
    create(
      :channel,
      title:       "Soulslike Central",
      handle:      "@soulslike",
      description: "Deep dives on hard games.",
      keywords:    "soulslike, action rpg",
      tags:        %w[bosses lore]
    )
  end
  let(:client) { instance_double(Voyage::Client) }

  before do
    AppSetting.singleton_row.update!(voyage_api_key: "test-key")
    allow(Voyage::Client).to receive(:new).and_return(client)
    allow(client).to receive(:embed).and_return([ Array.new(1024, 0.1) ])
  end

  it "embeds and stores the digest on first index" do
    expect { described_class.call(channel) }.to change { channel.reload.embedded_digest }.from(nil)
    expect(channel.summary_embedding).to be_present
  end

  it "includes title, handle, description, keywords, and tags in the embedded text" do
    expect(client).to receive(:embed) do |inputs|
      text = inputs.first
      expect(text).to include("Soulslike Central")
      expect(text).to include("@soulslike")
      expect(text).to include("Deep dives on hard games.")
      expect(text).to include("soulslike, action rpg")
      expect(text).to include("bosses lore")
      [ Array.new(1024, 0.1) ]
    end
    described_class.call(channel)
  end

  it "no-ops when the indexed text is unchanged" do
    described_class.call(channel)
    expect(client).not_to receive(:embed)
    described_class.call(channel.reload)
  end

  it "re-embeds when an indexed field changes" do
    described_class.call(channel)
    channel.update_column(:description, "A totally different focus now.")
    expect(client).to receive(:embed).and_return([ Array.new(1024, 0.2) ])
    described_class.call(channel.reload)
  end

  it "force: re-embeds even when the digest is unchanged" do
    described_class.call(channel)
    expect(client).to receive(:embed).and_return([ Array.new(1024, 0.3) ])
    described_class.call(channel.reload, force: true)
  end

  it "no-ops when Voyage is not configured" do
    AppSetting.singleton_row.update!(voyage_api_key: nil)
    expect(client).not_to receive(:embed)
    described_class.call(channel)
  end

  it "no-ops when every indexed field is blank" do
    blank = create(:channel, title: nil, handle: nil, description: nil, keywords: nil, tags: [])
    expect(client).not_to receive(:embed)
    described_class.call(blank)
  end
end
