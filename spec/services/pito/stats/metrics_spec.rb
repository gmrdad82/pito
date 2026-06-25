# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Stats::Metrics do
  describe ".label" do
    it "resolves the title-case word via Pito::Copy" do
      expect(described_class.label(:subs)).to eq("Subs")
      expect(described_class.label(:vids)).to eq("Vids")
      expect(described_class.label(:views)).to eq("Views")
      expect(described_class.label(:likes)).to eq("Likes")
      expect(described_class.label(:comments)).to eq("Comments")
    end

    it "accepts string keys" do
      expect(described_class.label("subs")).to eq("Subs")
    end
  end

  describe ".icon / .icon?" do
    it "maps likes/comments to their Lucide icon names" do
      expect(described_class.icon(:likes)).to eq("thumbs-up")
      expect(described_class.icon(:comments)).to eq("message-square")
    end

    it "is icon? only for likes/comments" do
      expect(described_class.icon?(:likes)).to be(true)
      expect(described_class.icon?(:comments)).to be(true)
      expect(described_class.icon?(:subs)).to be(false)
      expect(described_class.icon?(:vids)).to be(false)
      expect(described_class.icon?(:views)).to be(false)
    end

    it "returns nil icon for word metrics" do
      expect(described_class.icon(:views)).to be_nil
    end
  end
end
