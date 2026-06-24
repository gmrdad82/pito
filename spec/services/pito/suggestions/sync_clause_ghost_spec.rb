# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Suggestions::SyncClauseGhost do
  def ghost(text)
    described_class.ghost(text)
  end

  # ── CONNECTOR context — suggest `with` after "sync channels " ────────────────

  describe "CONNECTOR context — `with` suggestion" do
    it "ghosts 'with' for 'sync channels '" do
      result = ghost("sync channels ")
      expect(result).not_to be_nil
      expect(result[:complete_current]).to eq("with")
      expect(result[:next_hint]).to eq("")
    end

    it "completes 'w' → 'ith' for 'sync channels w'" do
      result = ghost("sync channels w")
      expect(result[:complete_current]).to eq("ith")
    end

    it "completes 'wi' → 'th' for 'sync channels wi'" do
      result = ghost("sync channels wi")
      expect(result[:complete_current]).to eq("th")
    end

    it "returns '' when partial is ambiguous or matches nothing (e.g. 'x')" do
      result = ghost("sync channels x")
      expect(result[:complete_current]).to eq("")
    end
  end

  # ── WITH context — suggest `vids` after "sync channels with " ────────────────

  describe "WITH context — `vids` suggestion" do
    it "ghosts 'vids' for 'sync channels with '" do
      result = ghost("sync channels with ")
      expect(result).not_to be_nil
      expect(result[:complete_current]).to eq("vids")
      expect(result[:next_hint]).to eq("")
    end

    it "completes 'v' → 'ids' for 'sync channels with v'" do
      result = ghost("sync channels with v")
      expect(result[:complete_current]).to eq("ids")
    end

    it "completes 'vi' → 'ds' for 'sync channels with vi'" do
      result = ghost("sync channels with vi")
      expect(result[:complete_current]).to eq("ds")
    end

    it "returns '' when partial matches nothing" do
      result = ghost("sync channels with zzz")
      expect(result[:complete_current]).to eq("")
    end
  end

  # ── Fall-through — returns nil when no channels noun is present ──────────────

  describe "fall-through (no channels noun)" do
    it "returns nil for 'sync '" do
      expect(ghost("sync ")).to be_nil
    end

    it "returns nil for 'sync videos '" do
      expect(ghost("sync videos ")).to be_nil
    end

    it "returns nil for bare 'sync'" do
      expect(ghost("sync")).to be_nil
    end
  end
end
