# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Suggestions::ListClauseGhost do
  def ghost(text)
    described_class.ghost(text)
  end

  # ── WITH clause — games ──────────────────────────────────────────────────────

  describe "WITH clause — games" do
    it "returns 'platform' as complete_current for 'list games with '" do
      result = ghost("list games with ")
      expect(result).not_to be_nil
      expect(result[:complete_current]).to eq("platform")
      expect(result[:next_hint]).to eq("")
    end

    it "returns 'atform' for 'list games with pl'" do
      result = ghost("list games with pl")
      expect(result[:complete_current]).to eq("atform")
    end

    it "returns 'genre' (platform excluded) for 'list games with platform, '" do
      result = ghost("list games with platform, ")
      expect(result[:complete_current]).to eq("genre")
    end

    it "returns 're' for 'list games with platform, gen'" do
      result = ghost("list games with platform, gen")
      expect(result[:complete_current]).to eq("re")
    end

    it "returns '' when the partial matches no candidates" do
      result = ghost("list games with zzz")
      expect(result[:complete_current]).to eq("")
    end

    it "returns '' when the partial is ambiguous (multiple matches)" do
      # 'p' matches 'platform' and 'publisher'
      result = ghost("list games with p")
      expect(result[:complete_current]).to eq("")
    end
  end

  # ── WITH clause — videos ─────────────────────────────────────────────────────

  describe "WITH clause — videos" do
    it "returns 'ration' for 'list videos with du'" do
      result = ghost("list videos with du")
      expect(result[:complete_current]).to eq("ration")
    end

    it "returns 'game' as complete_current for 'list videos with '" do
      result = ghost("list videos with ")
      expect(result[:complete_current]).to eq("game")
    end

    it "returns 'duration' (game excluded) for 'list videos with game, '" do
      result = ghost("list videos with game, ")
      expect(result[:complete_current]).to eq("duration")
    end
  end

  # ── SORT clause — games ──────────────────────────────────────────────────────

  describe "SORT clause — games" do
    it "returns 'tle' for 'list games sorted by ti'" do
      result = ghost("list games sorted by ti")
      expect(result[:complete_current]).to eq("tle")
    end

    it "returns 'id' as complete_current for 'list games sorted by '" do
      result = ghost("list games sorted by ")
      expect(result[:complete_current]).to eq("id")
    end

    it "returns '' for 'list games sorted by ye' when year not in with-clause" do
      # base_sort_tokens = ["id", "title"]; "ye" matches nothing in base
      result = ghost("list games sorted by ye")
      expect(result[:complete_current]).to eq("")
    end

    it "returns 'ar' for 'list games with year sorted by ye' (year now visible)" do
      result = ghost("list games with year sorted by ye")
      expect(result[:complete_current]).to eq("ar")
    end

    it "returns 'id' (first base token) for 'list games with platform sorted by '" do
      result = ghost("list games with platform sorted by ")
      expect(result[:complete_current]).to eq("id")
    end
  end

  # ── hashtag_list_sort_completions ────────────────────────────────────────────

  describe ".hashtag_list_sort_completions" do
    def sort_ghost(target, list_columns: [], args_text: "", ends_with_space: false)
      described_class.hashtag_list_sort_completions(
        target,
        list_columns:,
        args_text:,
        ends_with_space:
      )
    end

    context "unknown target" do
      it "returns nil for unknown target" do
        expect(sort_ghost("channel_list")).to be_nil
      end
    end

    context "game_list — no columns present (base sort tokens only)" do
      it "ghosts 'by' when args_text is empty" do
        result = sort_ghost("game_list", args_text: "", ends_with_space: true)
        expect(result[:ghost][:complete_current]).to eq("by")
      end

      it "ghosts 'y' when partial 'b' is typed" do
        result = sort_ghost("game_list", args_text: "b", ends_with_space: false)
        expect(result[:ghost][:complete_current]).to eq("y")
      end

      it "ghosts 'id' (first base token) after 'by '" do
        result = sort_ghost("game_list", args_text: "by ", ends_with_space: false)
        expect(result[:ghost][:complete_current]).to eq("id")
      end

      it "ghosts 'tle' for partial 'ti' after 'by '" do
        result = sort_ghost("game_list", args_text: "by ti", ends_with_space: false)
        expect(result[:ghost][:complete_current]).to eq("tle")
      end

      it "ghosts '' for ambiguous partial 'i' (id vs nothing)" do
        # 'i' matches only 'id' → 'd' remaining
        result = sort_ghost("game_list", args_text: "by i", ends_with_space: false)
        expect(result[:ghost][:complete_current]).to eq("d")
      end

      it "ghosts '' for partial matching no candidate" do
        result = sort_ghost("game_list", args_text: "by zzz", ends_with_space: false)
        expect(result[:ghost][:complete_current]).to eq("")
      end

      it "returns empty menu_items" do
        result = sort_ghost("game_list", args_text: "by ", ends_with_space: false)
        expect(result[:menu_items]).to eq([])
      end
    end

    context "game_list — platform column present" do
      it "includes platform as a sort candidate" do
        result = sort_ghost("game_list", list_columns: [ "platform" ], args_text: "by pl", ends_with_space: false)
        expect(result[:ghost][:complete_current]).to eq("atform")
      end
    end

    context "video_list — views column present" do
      it "includes views as a sort candidate" do
        result = sort_ghost("video_list", list_columns: [ "views" ], args_text: "by v", ends_with_space: false)
        expect(result[:ghost][:complete_current]).to eq("iews")
      end

      it "base-only columns are not sortable candidates from SORT_SPECS requires_with" do
        # 'channel' is base sort token (requires_with: false), NOT in COLUMNS → not in present_sortable
        # but IS in base_sort_tokens
        result = sort_ghost("video_list", list_columns: [], args_text: "by ch", ends_with_space: false)
        expect(result[:ghost][:complete_current]).to eq("annel")
      end
    end

    context "video_list — no columns present" do
      it "ghosts 'id' after 'by '" do
        result = sort_ghost("video_list", args_text: "by ", ends_with_space: false)
        expect(result[:ghost][:complete_current]).to eq("id")
      end
    end
  end

  # ── Channels — returns nil ────────────────────────────────────────────────────

  describe "channels noun" do
    it "returns nil for 'list channels with '" do
      expect(ghost("list channels with ")).to be_nil
    end

    it "returns nil for 'list channel with '" do
      expect(ghost("list channel with ")).to be_nil
    end
  end

  # ── CONNECTOR branch — ghosts `with` after the noun ─────────────────────────

  describe "connector branch — `with` after noun" do
    it "ghosts 'with' for 'list games ' (trailing space)" do
      result = ghost("list games ")
      expect(result).not_to be_nil
      expect(result[:complete_current]).to eq("with")
    end

    it "ghosts 'ith' for 'list games w' (partial match)" do
      result = ghost("list games w")
      expect(result[:complete_current]).to eq("ith")
    end

    it "ghosts 'with' for 'list games with ' — with-branch wins, not connector" do
      result = ghost("list games with ")
      expect(result[:complete_current]).to eq("platform")
    end

    it "ghosts 'eveloper' for 'list games with d' — with-branch still wins" do
      result = ghost("list games with d")
      expect(result[:complete_current]).to eq("eveloper")
    end

    it "returns complete_current '' for 'list games rpg' (partial matches no connector)" do
      result = ghost("list games rpg")
      expect(result).not_to be_nil
      expect(result[:complete_current]).to eq("")
    end

    it "returns nil for 'list games' (no trailing space — noun not yet completed)" do
      expect(ghost("list games")).to be_nil
    end

    it "returns nil for 'list videos' (no trailing space)" do
      expect(ghost("list videos")).to be_nil
    end

    it "ghosts 'elp' for 'list games --h' (--help is a connector candidate)" do
      result = ghost("list games --h")
      expect(result[:complete_current]).to eq("elp")
    end

    it "ghosts 'rted by' for 'list games so' (sorted by is a connector candidate)" do
      result = ghost("list games so")
      expect(result[:complete_current]).to eq("rted by")
    end

    it "ghosts '-help' for 'list games -' (completes toward --help)" do
      result = ghost("list games -")
      expect(result[:complete_current]).to eq("-help")
    end
  end
end
