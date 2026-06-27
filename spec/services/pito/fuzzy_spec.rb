# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Fuzzy do
  describe ".levenshtein" do
    def lev(a, b) = described_class.levenshtein(a, b)

    context "identical strings" do
      it "returns 0 for two identical non-empty strings" do
        expect(lev("hello", "hello")).to eq(0)
      end

      it "returns 0 for two empty strings" do
        expect(lev("", "")).to eq(0)
      end
    end

    context "empty vs non-empty" do
      it "returns b.length when a is empty" do
        expect(lev("", "abc")).to eq(3)
      end

      it "returns a.length when b is empty" do
        expect(lev("abc", "")).to eq(3)
      end
    end

    context "single operations" do
      it "returns 1 for a single substitution" do
        # "abc" → "axc": one substitution (b→x)
        expect(lev("abc", "axc")).to eq(1)
      end

      it "returns 1 for a single insertion" do
        # "abc" → "abcd": one insertion
        expect(lev("abc", "abcd")).to eq(1)
      end

      it "returns 1 for a single deletion" do
        # "abcd" → "abc": one deletion
        expect(lev("abcd", "abc")).to eq(1)
      end
    end

    context "known distances" do
      # kitten → sitten (k→s), sitten → sittin (e→i), sittin → sitting (+g) = 3
      it { expect(lev("kitten", "sitting")).to eq(3) }

      # "resume" vs "resome": u→o substitution at position 4 = 1
      it { expect(lev("resume", "resome")).to eq(1) }

      # "hello" vs "world": 4 ops (verified via DP)
      it { expect(lev("hello", "world")).to eq(4) }
    end

    context "nil safety (.to_s coercion)" do
      it "treats nil a as empty string — returns b.length" do
        expect(lev(nil, "abc")).to eq(3)
      end

      it "treats nil b as empty string — returns a.length" do
        expect(lev("abc", nil)).to eq(3)
      end

      it "returns 0 when both args are nil" do
        expect(lev(nil, nil)).to eq(0)
      end
    end
  end
end
