# frozen_string_literal: true

require "rails_helper"

# Ai::Blocks is the sole gate between the model's typed pito_respond blocks and
# what actually renders: every type is validated/clamped, and a block that
# fails its rules DEGRADES to a text block carrying its own JSON — never nil,
# never a raise. Each context below drives one type's happy path plus its
# documented degrade path(s).
RSpec.describe Ai::Blocks do
  let(:conversation) { Conversation.singleton }

  def normalize(raw)
    described_class.normalize(raw, conversation:)
  end

  describe ".text_block" do
    it "wraps a string as a text block" do
      expect(described_class.text_block("x")).to eq({ "type" => "text", "text" => "x" })
    end
  end

  describe ".normalize" do
    context "text blocks" do
      it "passes valid text trimmed" do
        result = normalize([ { "type" => "text", "text" => "  hi  " } ])
        expect(result).to eq([ { "type" => "text", "text" => "hi" } ])
      end

      it "caps text at 4000 chars" do
        result = normalize([ { "type" => "text", "text" => "a" * 5_000 } ])
        expect(result.first["text"].length).to eq(4_000)
      end

      it "drops (does not degrade) a blank text block" do
        expect(normalize([ { "type" => "text", "text" => "   " } ])).to eq([])
      end

      it "extracts a markdown pipe-table into a real table block between the prose" do
        leaked = "Games to try:\n| # | Game | Score |\n|---|------|-------|\n| 12 | Elden Ring | 94 |\n| 18 | Nioh 3 | 84 |\nPick one."
        result = normalize([ { "type" => "text", "text" => leaked } ])

        expect(result.map { |b| b["type"] }).to eq(%w[text table text])
        expect(result[1]["header"]).to eq([ "#", "Game", "Score" ])
        expect(result[1]["rows"]).to eq([ [ "12", "Elden Ring", "94" ], [ "18", "Nioh 3", "84" ] ])
        expect(result[0]["text"]).to eq("Games to try:")
        expect(result[2]["text"]).to eq("Pick one.")
      end

      it "leaves pipe lines without a |---| separator as plain text" do
        value  = "| not | a table |\n| just | pipes |"
        result = normalize([ { "type" => "text", "text" => value } ])
        expect(result).to eq([ { "type" => "text", "text" => value } ])
      end

      it "keeps the block cap after a table split" do
        leaked = "t\n| a | b |\n|---|---|\n| 1 | 2 |\nrest"
        result = normalize(Array.new(12) { { "type" => "text", "text" => leaked } })
        expect(result.length).to eq(12)
      end

      it "scrubs a parroted history marker embedded in prose" do
        result = normalize([ { "type" => "text", "text" => "Here's the data.\n[kv_table block shown]\nMore info." } ])
        expect(result).to eq([ { "type" => "text", "text" => "Here's the data.\n\nMore info." } ])
      end

      it "drops a text block that is only a history marker" do
        expect(normalize([ { "type" => "text", "text" => "[kv_table block shown]" } ])).to eq([])
        expect(normalize([ { "type" => "text", "text" => "(chart rendered)" } ])).to eq([])
      end

      it "leaves a suggested-command bracket untouched" do
        result = normalize([ { "type" => "text", "text" => "Try [suggested command: show game #1] next." } ])
        expect(result).to eq([ { "type" => "text", "text" => "Try [suggested command: show game #1] next." } ])
      end
    end

    context "kv_table blocks" do
      it "passes valid 2-column rows" do
        result = normalize([ { "type" => "kv_table", "rows" => [ %w[score 84], %w[hours 12] ] } ])
        expect(result).to eq([ { "type" => "kv_table", "rows" => [ %w[score 84], %w[hours 12] ] } ])
      end

      it "clamps rows beyond 20" do
        rows   = Array.new(25) { |i| [ "k#{i}", "v#{i}" ] }
        result = normalize([ { "type" => "kv_table", "rows" => rows } ])

        expect(result.first["rows"].size).to eq(20)
      end

      it "degrades when no row is a valid pair" do
        result = normalize([ { "type" => "kv_table", "rows" => [ [ "solo" ], %w[a b c] ] } ])

        expect(result.first["type"]).to eq("text")
        expect(result.first["text"]).to include("kv_table")
      end
    end

    context "kv_table plain-datetime promotion (WP-B)" do
      it "promotes a plain ISO date value to a typed date" do
        result = normalize([ { "type" => "kv_table", "rows" => [ [ "Release", "2026-07-19" ] ] } ])
        expect(result.first["rows"]).to eq([ [ "Release", { "v" => "2026-07-19", "format" => "date" } ] ])
      end

      it "promotes a plain ISO datetime value to a typed date" do
        result = normalize([ { "type" => "kv_table", "rows" => [ [ "Synced", "2026-07-19T14:30:00Z" ] ] } ])
        expect(result.first["rows"]).to eq([ [ "Synced", { "v" => "2026-07-19T14:30:00Z", "format" => "date" } ] ])
      end

      it "promotes a plain house-format date (dd-mm-yyyy) value to a typed date" do
        result = normalize([ { "type" => "kv_table", "rows" => [ [ "Release", "19-07-2026" ] ] } ])
        expect(result.first["rows"]).to eq([ [ "Release", { "v" => "19-07-2026", "format" => "date" } ] ])
      end

      it "promotes a plain house-format datetime (dd-mm-yyyy hh:mm) value to a typed date" do
        result = normalize([ { "type" => "kv_table", "rows" => [ [ "Synced", "19-07-2026 14:30" ] ] } ])
        expect(result.first["rows"]).to eq([ [ "Synced", { "v" => "19-07-2026 14:30", "format" => "date" } ] ])
      end

      it "leaves an ordinary plain string alone (not a date)" do
        result = normalize([ { "type" => "kv_table", "rows" => [ [ "Genre", "RPG" ] ] } ])
        expect(result.first["rows"]).to eq([ [ "Genre", "RPG" ] ])
      end

      it "leaves a shape-matching but calendar-invalid date string alone" do
        result = normalize([ { "type" => "kv_table", "rows" => [ [ "Release", "31-13-2026" ] ] } ])
        expect(result.first["rows"]).to eq([ [ "Release", "31-13-2026" ] ])
      end

      it "does not re-promote an already-typed date value" do
        result = normalize([ { "type" => "kv_table", "rows" => [
          [ "Release", { "v" => "2026-07-19", "format" => "date" } ]
        ] } ])
        expect(result.first["rows"]).to eq([ [ "Release", { "v" => "2026-07-19", "format" => "date" } ] ])
      end

      it "keeps a show command on a row, unaffected by date promotion" do
        result = normalize([ { "type" => "kv_table", "rows" => [
          { "key" => "#12 Elden Ring", "value" => "RPG", "command" => "show game #12" }
        ] } ])
        expect(result.first["rows"]).to eq([ [ "#12 Elden Ring", "RPG", "show game #12" ] ])
      end
    end

    context "table blocks" do
      it "degrades when the header is missing" do
        result = normalize([ { "type" => "table", "rows" => [ %w[a b] ] } ])
        expect(result.first["type"]).to eq("text")
      end

      it "pads short rows and truncates long rows to the header width" do
        result = normalize([ {
          "type" => "table", "header" => %w[a b c],
          "rows" => [ %w[1], %w[1 2 3 4] ]
        } ])

        expect(result).to eq([ {
          "type" => "table", "header" => %w[a b c],
          "rows" => [ [ "1", "", "" ], %w[1 2 3] ]
        } ])
      end

      it "caps the header at 6 columns and rows at 20" do
        header = ("a".."z").first(8)
        rows   = Array.new(25) { |i| [ "r#{i}" ] * 8 }
        result = normalize([ { "type" => "table", "header" => header, "rows" => rows } ])

        expect(result.first["header"].size).to eq(6)
        expect(result.first["rows"].size).to eq(20)
        expect(result.first["rows"].first.size).to eq(6)
      end
    end

    context "media blocks" do
      it "passes a valid game id with the default cover variant" do
        game   = create(:game)
        result = normalize([ { "type" => "media", "entity" => "game", "id" => game.id } ])

        expect(result).to eq([ { "type" => "media", "entity" => "game", "id" => game.id, "variant" => "cover" } ])
      end

      it "degrades an unknown entity" do
        result = normalize([ { "type" => "media", "entity" => "widget", "id" => 1 } ])
        expect(result.first["type"]).to eq("text")
      end

      it "degrades a nonexistent id" do
        result = normalize([ { "type" => "media", "entity" => "game", "id" => 999_999_999 } ])
        expect(result.first["type"]).to eq("text")
      end

      it "keeps a valid channel variant and falls back on a bogus one" do
        channel = create(:channel)

        kept = normalize([ { "type" => "media", "entity" => "channel", "id" => channel.id, "variant" => "banner" } ])
        expect(kept.first["variant"]).to eq("banner")

        fallback = normalize([ { "type" => "media", "entity" => "channel", "id" => channel.id, "variant" => "bogus" } ])
        expect(fallback.first["variant"]).to eq("avatar")
      end
    end

    context "sparkline blocks" do
      it "clamps negative values to 0 and length to 90" do
        series = [ -5, 3 ] + Array.new(95, 1)
        result = normalize([ { "type" => "sparkline", "series" => series } ])

        expect(result.first["series"].size).to eq(90)
        expect(result.first["series"].first(2)).to eq([ 0.0, 3.0 ])
      end

      it "degrades an empty series" do
        result = normalize([ { "type" => "sparkline", "series" => [] } ])
        expect(result.first["type"]).to eq("text")
      end

      it "coerces series_max" do
        result = normalize([ { "type" => "sparkline", "series" => [ 1 ], "series_max" => "42" } ])
        expect(result.first["series_max"]).to eq(42.0)
      end
    end

    context "chart blocks" do
      it "passes valid bar entries, clamping pct and carrying an optional value_label" do
        bars = [
          { "label" => "A", "pct" => 150, "value_label" => "3h" },
          { "label" => "B", "pct" => -5 }
        ]
        result = normalize([ { "type" => "chart", "viz" => "bar", "data" => { "bars" => bars } } ])

        # The negative bar clamps down to zero and is then dropped like any
        # zero bucket (owner law: a bar with nothing to show never renders).
        expect(result).to eq([ {
          "type" => "chart", "viz" => "bar",
          "bars" => [
            { "label" => "A", "pct" => 100.0, "value_label" => "3h" }
          ]
        } ])
      end

      it "drops bar entries missing a label, degrading when all are dropped" do
        result = normalize([ { "type" => "chart", "viz" => "bar", "data" => { "bars" => [ { "pct" => 50 } ] } } ])
        expect(result.first["type"]).to eq("text")
      end

      it "passes a bare-7 heatmap (the weekday preset — no labels key)" do
        ok = normalize([ { "type" => "chart", "viz" => "heatmap", "data" => { "values" => [ 1, 2, 3, 4, 5, 6, 7 ] } } ])
        expect(ok).to eq([ { "type" => "chart", "viz" => "heatmap", "values" => [ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0 ] } ])
      end

      it "passes any 2..42 heatmap values with matching labels, plain()-ed" do
        ok = normalize([ { "type" => "chart", "viz" => "heatmap",
                           "data" => { "values" => [ 1, 2, 3 ], "labels" => [ "**Q1**", "Q2", "Q3" ] } } ])
        expect(ok).to eq([ { "type" => "chart", "viz" => "heatmap",
                             "values" => [ 1.0, 2.0, 3.0 ], "labels" => %w[Q1 Q2 Q3] } ])
      end

      it "degrades a heatmap outside 2..42 values" do
        one = normalize([ { "type" => "chart", "viz" => "heatmap", "data" => { "values" => [ 1 ] } } ])
        expect(one.first["type"]).to eq("text")

        many = normalize([ { "type" => "chart", "viz" => "heatmap", "data" => { "values" => (1..43).to_a } } ])
        expect(many.first["type"]).to eq("text")
      end

      it "degrades a heatmap whose labels don't pair 1:1 with values" do
        bad = normalize([ { "type" => "chart", "viz" => "heatmap",
                            "data" => { "values" => [ 1, 2, 3 ], "labels" => %w[a b] } } ])
        expect(bad.first["type"]).to eq("text")
      end

      it "maps an area viz's series like a sparkline" do
        result = normalize([ { "type" => "chart", "viz" => "area", "data" => { "series" => [ -3, 4 ] } } ])
        expect(result.first["series"]).to eq([ 0.0, 4.0 ])
      end

      it "degrades an unknown viz" do
        result = normalize([ { "type" => "chart", "viz" => "pie", "data" => {} } ])
        expect(result.first["type"]).to eq("text")
      end
    end

    context "chart heart blocks" do
      it "clamps score and floors the legend counts" do
        result = normalize([ { "type" => "chart", "viz" => "heart",
                               "data" => { "score" => 130, "likes" => -3, "dislikes" => "7" }, "label" => "loved?" } ])
        expect(result).to eq([ { "type" => "chart", "viz" => "heart",
                                 "score" => 100, "likes" => 0, "dislikes" => 7, "label" => "loved?" } ])
      end

      it "degrades a heart without a score" do
        result = normalize([ { "type" => "chart", "viz" => "heart", "data" => { "likes" => 1 } } ])
        expect(result.first["type"]).to eq("text")
      end
    end

    context "score blocks" do
      it "clamps an integer value to 0..100" do
        result = normalize([ { "type" => "score", "value" => 250 } ])
        expect(result.first["value"]).to eq(100)
      end

      it "degrades a non-numeric value" do
        result = normalize([ { "type" => "score", "value" => "high" } ])
        expect(result.first["type"]).to eq("text")
      end

      it "carries an optional label" do
        result = normalize([ { "type" => "score", "value" => 50, "label" => "Fun" } ])
        expect(result.first["label"]).to eq("Fun")
      end
    end

    context "ttb blocks" do
      it "degrades when hours.main is not greater than 0" do
        result = normalize([ { "type" => "ttb", "hours" => { "main" => 0 } } ])
        expect(result.first["type"]).to eq("text")
      end

      it "maps the legacy game shape onto levels, dropping absent tiers, footage → current" do
        result = normalize([ {
          "type" => "ttb",
          "hours" => { "main" => 10, "extras" => -2, "completionist" => -1 },
          "footage_hours" => 5
        } ])

        expect(result).to eq([ {
          "type"    => "ttb",
          "levels"  => [ { "label" => "main", "hours" => 10.0 } ],
          "current" => { "label" => "footage", "hours" => 5.0 }
        } ])
      end

      it "accepts the generic shape: ordered labelled levels + a current tracker" do
        result = normalize([ {
          "type"   => "ttb",
          "levels" => [
            { "label" => "level 1", "hours" => 5 },
            { "label" => "level 2", "hours" => 20 },
            { "label" => "level 3", "hours" => 50 },
            { "label" => "level 4 overflow", "hours" => 99 }
          ],
          "current" => { "label" => "so far", "hours" => -3 }
        } ])

        expect(result).to eq([ {
          "type"    => "ttb",
          "levels"  => [
            { "label" => "level 1", "hours" => 5.0 },
            { "label" => "level 2", "hours" => 20.0 },
            { "label" => "level 3", "hours" => 50.0 }
          ],
          "current" => { "label" => "so far", "hours" => 0.0 }
        } ])
      end
    end

    context "suggestion blocks" do
      it "passes a command that parses as a real verb" do
        result = normalize([ { "type" => "suggestion", "command" => "list games" } ])
        expect(result).to eq([ { "type" => "suggestion", "command" => "list games" } ])
      end

      it "degrades a garbage command" do
        result = normalize([ { "type" => "suggestion", "command" => "frobnicate the vibes" } ])
        expect(result.first["type"]).to eq("text")
      end

      it "degrades ai (recursion)" do
        result = normalize([ { "type" => "suggestion", "command" => "ai hello" } ])
        expect(result.first["type"]).to eq("text")
      end

      it "degrades the 2nd+ suggestion beyond the 1-suggestion cap" do
        blocks = Array.new(3) { { "type" => "suggestion", "command" => "list games" } }
        result = normalize(blocks)

        expect(result.first(1)).to all(include("type" => "suggestion"))
        expect(result.drop(1)).to all(include("type" => "text"))
      end
    end
  end

  describe ".normalize overall shape" do
    it "truncates to 12 blocks" do
      blocks = Array.new(15) { { "type" => "text", "text" => "x" } }
      expect(normalize(blocks).size).to eq(12)
    end

    it "keeps the closing suggestion when the answer overflows the block cap" do
      blocks = Array.new(14) { { "type" => "text", "text" => "x" } } +
               [ { "type" => "suggestion", "command" => "list games" } ]
      result = normalize(blocks)

      expect(result.size).to eq(12)
      expect(result.last).to eq({ "type" => "suggestion", "command" => "list games" })
    end

    it ".cap swaps the suggestion in for the last kept block when the trim would drop it" do
      blocks = Array.new(14) { { "type" => "text", "text" => "x" } } +
               [ { "type" => "suggestion", "command" => "list games" } ]
      capped = described_class.cap(blocks)

      expect(capped.size).to eq(12)
      expect(capped.first(11)).to all(include("type" => "text"))
      expect(capped.last["type"]).to eq("suggestion")
    end

    it "drops non-Hash entries entirely" do
      result = normalize([ "just a string", { "type" => "text", "text" => "ok" } ])
      expect(result).to eq([ { "type" => "text", "text" => "ok" } ])
    end

    it "degrades an unknown type" do
      result = normalize([ { "type" => "mystery" } ])
      expect(result.first["type"]).to eq("text")
    end

    it "deep-stringifies symbol-keyed input" do
      result = normalize([ { type: "text", text: "sym" } ])
      expect(result).to eq([ { "type" => "text", "text" => "sym" } ])
    end
  end
  describe "chart viz=bar zero buckets (owner law)" do
    it "drops zero-value bars and keeps the rest" do
      block = { "type" => "chart", "viz" => "bar", "data" => { "bars" => [
        { "label" => "A", "pct" => 60.0 }, { "label" => "Others", "pct" => 0 },
        { "label" => "B", "pct" => 40.0 }
      ] } }
      out = described_class.normalize([ block ], conversation: nil).first
      expect(out["type"]).to eq("chart")
      expect(out["bars"].map { |b| b["label"] }).to eq(%w[A B])
    end

    it "degrades the block when every bar is zero" do
      block = { "type" => "chart", "viz" => "bar", "data" => { "bars" => [
        { "label" => "Others", "pct" => 0 }
      ] } }
      out = described_class.normalize([ block ], conversation: nil).first
      expect(out["type"]).to eq("text")
    end
  end
end
