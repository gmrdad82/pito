# frozen_string_literal: true

require "rails_helper"

# ── Share copy dict completeness guard ───────────────────────────────────────
#
# Asserts the three share locale dicts have the required number of variants.
# The general dictionary_guard_spec enforces the 1-or-50 rule globally; these
# targeted specs fail fast with explicit names when a share dict is short.

RSpec.describe "Share copy dicts", type: :locale do
  before { I18n.reload! }

  describe "pito.copy.share.intro" do
    subject(:variants) { I18n.t("pito.copy.share.intro") }

    it "is an Array" do
      expect(variants).to be_an(Array)
    end

    it "has exactly 50 variants" do
      expect(variants.length).to eq(50)
    end

    it "every variant interpolates %{count} without error" do
      variants.each do |v|
        expect { v % { count: 7 } }.not_to raise_error
      end
    end
  end

  describe "pito.copy.share.outro" do
    subject(:variants) { I18n.t("pito.copy.share.outro") }

    it "is an Array" do
      expect(variants).to be_an(Array)
    end

    it "has exactly 50 variants" do
      expect(variants.length).to eq(50)
    end

    it "every variant interpolates %{count} without error" do
      variants.each do |v|
        expect { v % { count: 3 } }.not_to raise_error
      end
    end
  end

  describe "pito.copy.share.unfold_hint" do
    subject(:value) { I18n.t("pito.copy.share.unfold_hint") }

    it "is a single string (not an array)" do
      expect(value).to be_a(String)
    end

    it "is not blank" do
      expect(value).not_to be_blank
    end
  end
end
