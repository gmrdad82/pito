require "rails_helper"

RSpec.describe Search::Engine do
  subject { described_class.new }

  describe "abstract interface" do
    it "raises NotImplementedError for #index" do
      expect { subject.index(nil) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #remove" do
      expect { subject.remove(nil) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #reindex_all" do
      expect { subject.reindex_all(nil) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #search" do
      expect { subject.search(nil, "q") }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #healthy?" do
      expect { subject.healthy? }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #index_stats" do
      expect { subject.index_stats }.to raise_error(NotImplementedError)
    end

    # 2026-05-11 — `total_index_size_bytes` is an OPTIONAL method.
    # Engines that don't expose an on-disk size metric (or future
    # alternatives) inherit the default `nil` return so the
    # settings view hides the row gracefully.
    it "returns nil from #total_index_size_bytes by default" do
      expect(subject.total_index_size_bytes).to be_nil
    end

    # 2026-05-11 (later 2) — `per_index_stats` is also OPTIONAL.
    # Engines that don't expose per-index document counts + size
    # inherit `{}` so the settings view hides the breakdown table
    # gracefully.
    it "returns {} from #per_index_stats by default" do
      expect(subject.per_index_stats).to eq({})
    end
  end
end
