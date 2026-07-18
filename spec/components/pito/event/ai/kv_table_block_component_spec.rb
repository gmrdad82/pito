# frozen_string_literal: true

require "rails_helper"

# Pito::Event::Ai::KvTableBlockComponent renders one KeyValueRowComponent per
# normalized Ai::Blocks kv_table row ([key, value] or [key, value, command]).
# WP-B mobile polish: label truncation, the house SyncStamp date format, and
# the id-token list-cell treatment for `show vid|game|channel #<id>` rows.
RSpec.describe Pito::Event::Ai::KvTableBlockComponent, type: :component do
  describe "grid + truncation" do
    it "renders one grid wrapper with the minmax(0, max-content) label column" do
      node = render_inline(described_class.new(rows: [ [ "Genre", "RPG" ] ]))
      grid = node.at_css("div.grid")

      expect(grid["class"]).to eq("grid grid-cols-[minmax(0,max-content)_1fr] gap-x-2 gap-y-1")
    end

    it "renders a colon-suffixed key + value span per row" do
      node = render_inline(described_class.new(rows: [ [ "Genre", "RPG" ], [ "Score", "84" ] ]))

      expect(node.css("span.text-cyan").map(&:text)).to eq([ "Genre:", "Score:" ])
      expect(node.text).to include("RPG").and include("84")
    end

    it "caps the key span at a fixed ch width and lets it truncate instead of widening the column" do
      node = render_inline(described_class.new(rows: [ [ "Genre", "RPG" ] ]))
      classes = node.at_css("span.text-cyan")["class"].split

      expect(classes).to include("whitespace-nowrap", "overflow-hidden", "text-ellipsis", "min-w-0", "max-w-[20ch]")
    end

    it "never touches KeyValueRowComponent's own defaults" do
      # Regression guard: the truncation classes are an override passed FROM
      # this component, not a change to the shared component's DEFAULT_KEY_CLASS.
      expect(Pito::Table::KeyValueRowComponent::DEFAULT_KEY_CLASS).to eq("text-cyan whitespace-nowrap")
    end
  end

  describe "house date format (typed values)" do
    it "renders a typed date with a time component through SyncStamp (DD-MM-YYYY HH:MM)" do
      rows = [ [ "Synced", { "v" => "2026-07-19T14:30:00", "format" => "date" } ] ]
      node = render_inline(described_class.new(rows: rows))

      expect(node.at_css("span.text-right").text).to eq("19-07-2026 14:30")
    end

    it "renders a typed house-format (dd-mm-yyyy hh:mm) datetime through SyncStamp" do
      rows = [ [ "Synced", { "v" => "19-07-2026 14:30", "format" => "date" } ] ]
      node = render_inline(described_class.new(rows: rows))

      expect(node.at_css("span.text-right").text).to eq("19-07-2026 14:30")
    end

    it "renders a date-only ISO value date-only (no invented midnight)" do
      rows = [ [ "Release", { "v" => "2026-07-19", "format" => "date" } ] ]
      node = render_inline(described_class.new(rows: rows))

      expect(node.at_css("span.text-right").text).to eq("19-07-2026")
    end

    it "renders a date-only house-format value date-only" do
      rows = [ [ "Release", { "v" => "19-07-2026", "format" => "date" } ] ]
      node = render_inline(described_class.new(rows: rows))

      expect(node.at_css("span.text-right").text).to eq("19-07-2026")
    end

    it "no longer renders the old US-order, tz-ignorant %b %-d, %Y shape" do
      rows = [ [ "Release", { "v" => "2026-07-19", "format" => "date" } ] ]
      node = render_inline(described_class.new(rows: rows))

      expect(node.text).not_to include("Jul 19, 2026")
    end

    it "falls back to the raw string for an unparseable typed date" do
      rows = [ [ "Release", { "v" => "not-a-date", "format" => "date" } ] ]
      node = render_inline(described_class.new(rows: rows))

      expect(node.at_css("span.text-right").text).to eq("not-a-date")
    end
  end

  describe "actionable #id rows (show vid|game|channel)" do
    it "splits the leading #<id> into its own clickable list-cell token and drops the whole-key binding" do
      rows = [ [ "#42 Elden Ring", "RPG", "show game #42" ] ]
      node = render_inline(described_class.new(rows: rows))

      key_span = node.at_css("span.text-cyan")
      expect(key_span["data-controller"]).to be_nil
      expect(key_span.text).to eq("#42 Elden Ring:")

      id_token = node.at_css("span.pito-action-shimmer")
      expect(id_token.text).to eq("#42")
      expect(id_token["data-controller"]).to eq("pito--chat-prefill")
      expect(id_token["data-action"]).to eq("click->pito--chat-prefill#fill")
      expect(id_token["data-pito--chat-prefill-text-value"]).to eq("show game #42")
      expect(id_token["data-pito--chat-prefill-submit-value"]).to eq("true")
    end

    it "works for vid and channel show commands too" do
      rows = [
        [ "#17 A Vid", "Vid", "show vid #17" ],
        [ "#5 A Channel", "Channel", "show channel #5" ]
      ]
      node = render_inline(described_class.new(rows: rows))
      tokens = node.css("span.pito-action-shimmer")

      expect(tokens.map(&:text)).to eq([ "#17", "#5" ])
      expect(tokens.map { |t| t["data-pito--chat-prefill-text-value"] }).to eq([ "show vid #17", "show channel #5" ])
    end

    it "keeps today's whole-key stage-only behavior for a non-show command" do
      rows = [ [ "Status", "Scheduled", "list vids" ] ]
      node = render_inline(described_class.new(rows: rows))

      key_span = node.at_css("span.text-cyan")
      expect(key_span["data-controller"]).to eq("pito--chat-prefill")
      expect(key_span["data-pito--chat-prefill-text-value"]).to eq("list vids")
      expect(key_span["data-pito--chat-prefill-submit-value"]).to be_nil
      expect(node.at_css("span.pito-action-shimmer")).to be_nil
    end

    it "keeps a show command's whole-key stage-only behavior when the label has no leading #<id>" do
      rows = [ [ "Featured game", "RPG", "show game #42" ] ]
      node = render_inline(described_class.new(rows: rows))

      key_span = node.at_css("span.text-cyan")
      expect(key_span["data-controller"]).to eq("pito--chat-prefill")
      expect(key_span["data-pito--chat-prefill-text-value"]).to eq("show game #42")
      expect(node.at_css("span.pito-action-shimmer")).to be_nil
    end

    it "stays inert (no data attributes) when the row carries no command" do
      rows = [ [ "Genre", "RPG" ] ]
      node = render_inline(described_class.new(rows: rows))

      key_span = node.at_css("span.text-cyan")
      expect(key_span["data-controller"]).to be_nil
      expect(node.at_css("span.pito-action-shimmer")).to be_nil
    end
  end
end
