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
  end
end
