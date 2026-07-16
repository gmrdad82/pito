# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Stack::Local, type: :service do
  it "reports a positive database size in MB" do
    expect(described_class.db_size_mb).to be > 0
  end

  it "reports record counts for videos and games" do
    create(:game)
    counts = described_class.records
    expect(counts.keys).to contain_exactly(:videos, :games)
    expect(counts[:games]).to eq(Game.count)
    expect(counts[:videos]).to eq(Video.count)
  end

  it "to_h bundles size + records" do
    expect(described_class.to_h.keys).to contain_exactly(:db_size_mb, :records)
  end

  it "Pito::Stack.usage includes local" do
    expect(Pito::Stack.usage.keys).to include(:local, :youtube, :igdb)
  end
end
