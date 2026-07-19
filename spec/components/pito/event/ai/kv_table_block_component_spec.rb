# frozen_string_literal: true

require "rails_helper"

# Pito::Event::Ai::KvTableBlockComponent renders one KeyValueRowComponent per
# normalized Ai::Blocks kv_table row ([key, value] or [key, value, command]).
# WP-B mobile polish: label truncation, the house date/stamp format (SyncStamp
# for a time component, HouseDate.date for date-only), and the id-token
# list-cell treatment for `show vid|game|channel #<id>` rows. Also covers the
# table-alignment extension: a PLAIN value right-aligns when it shapes as a
# Pito::Event::Ai::CellShapes family (numeric / #id / date-time), same as a
# typed value — the key column and prose values are untouched.
RSpec.describe Pito::Event::Ai::KvTableBlockComponent, type: :component do
  include ActiveSupport::Testing::TimeHelpers

  describe "grid + truncation" do
    it "renders one grid wrapper with the fit-content(max(20ch,55%)) label column" do
      node = render_inline(described_class.new(rows: [ [ "Genre", "RPG" ] ]))
      grid = node.at_css("div.grid")

      expect(grid["class"]).to eq("grid grid-cols-[fit-content(max(20ch,55%))_minmax(0,1fr)] gap-x-2 gap-y-1")
    end

    it "renders a colon-suffixed key + value span per row" do
      node = render_inline(described_class.new(rows: [ [ "Genre", "RPG" ], [ "Score", "84" ] ]))

      expect(node.css("span.text-cyan").map(&:text)).to eq([ "Genre:", "Score:" ])
      expect(node.text).to include("RPG").and include("84")
    end

    it "keeps the key span truncation-ready but drops the old unconditional ch cap" do
      node = render_inline(described_class.new(rows: [ [ "Genre", "RPG" ] ]))
      classes = node.at_css("span.text-cyan")["class"].split

      # The cap now lives on the grid TRACK (fit-content(max(20ch,55%)) in the
      # wrapper's grid-cols-[...], asserted above) — the key span itself only
      # needs to be ready to ellipsis-truncate once that track actually
      # pinches; whether it visually does is a compiled-CSS concern (see the
      # scratch-build proof in the kv_table_block_component.rb KEY_CLASS
      # comment / the task's Tailwind CLI grep), not a unit-spec concern.
      expect(classes).to include("whitespace-nowrap", "overflow-hidden", "text-ellipsis", "min-w-0")
      expect(classes).not_to include("max-w-[20ch]")
    end

    it "never touches KeyValueRowComponent's own defaults" do
      # Regression guard: the truncation classes are an override passed FROM
      # this component, not a change to the shared component's DEFAULT_KEY_CLASS.
      expect(Pito::Table::KeyValueRowComponent::DEFAULT_KEY_CLASS).to eq("text-cyan whitespace-nowrap")
    end
  end

  describe "plain values that shape-align (Pito::Event::Ai::CellShapes)" do
    it "right-aligns a plain #id value" do
      node = render_inline(described_class.new(rows: [ [ "Linked", "#38" ] ]))
      value = node.css("span").find { |c| c.text == "#38" }

      expect(value["class"]).to include("text-right")
    end

    it "right-aligns a plain house date+time value" do
      node = render_inline(described_class.new(rows: [ [ "Synced", "19 Jul 12:00" ] ]))
      value = node.css("span").find { |c| c.text == "19 Jul 12:00" }

      expect(value["class"]).to include("text-right")
    end

    it "right-aligns a plain numeric value" do
      node = render_inline(described_class.new(rows: [ [ "Views", "7,709" ] ]))
      value = node.css("span").find { |c| c.text == "7,709" }

      expect(value["class"]).to include("text-right")
    end

    it "does not right-align plain prose" do
      node = render_inline(described_class.new(rows: [ [ "Genre", "RPG" ] ]))
      value = node.css("span").find { |c| c.text == "RPG" }

      expect(value["class"]).not_to include("text-right")
      expect(value["class"]).to eq(Pito::Table::KeyValueRowComponent::DEFAULT_VALUE_CLASS)
    end

    it "leaves typed-value alignment unchanged" do
      rows = [ [ "Price", { "v" => "9.99", "format" => "price" } ] ]
      node = render_inline(described_class.new(rows: rows))

      expect(node.at_css("span.text-right")["class"]).to eq("text-fg-dim text-right")
    end
  end

  describe "house date format (typed values)" do
    it "renders a typed date with a time component through SyncStamp — this year, not today" do
      travel_to(Time.zone.local(2026, 8, 1)) do
        rows = [ [ "Synced", { "v" => "2026-07-19T14:30:00", "format" => "date" } ] ]
        node = render_inline(described_class.new(rows: rows))

        expect(node.at_css("span.text-right").text).to eq("19 Jul 14:30")
      end
    end

    it "renders a typed house-format (dd-mm-yyyy hh:mm) datetime through SyncStamp — this year, not today" do
      travel_to(Time.zone.local(2026, 8, 1)) do
        rows = [ [ "Synced", { "v" => "19-07-2026 14:30", "format" => "date" } ] ]
        node = render_inline(described_class.new(rows: rows))

        expect(node.at_css("span.text-right").text).to eq("19 Jul 14:30")
      end
    end

    it "collapses a typed datetime that IS today to bare HH:MM (the date drops entirely)" do
      travel_to(Time.zone.local(2026, 7, 19, 9, 0)) do
        rows = [ [ "Synced", { "v" => "2026-07-19T14:30:00", "format" => "date" } ] ]
        node = render_inline(described_class.new(rows: rows))

        expect(node.at_css("span.text-right").text).to eq("14:30")
      end
    end

    it "renders a date-only ISO value through the house date — current year drops the year" do
      travel_to(Time.zone.local(2026, 8, 1)) do
        rows = [ [ "Release", { "v" => "2026-07-19", "format" => "date" } ] ]
        node = render_inline(described_class.new(rows: rows))

        expect(node.at_css("span.text-right").text).to eq("19 Jul")
      end
    end

    it "renders a date-only house-format (dd-mm-yyyy) value through the house date — current year drops the year" do
      travel_to(Time.zone.local(2026, 8, 1)) do
        rows = [ [ "Release", { "v" => "19-07-2026", "format" => "date" } ] ]
        node = render_inline(described_class.new(rows: rows))

        expect(node.at_css("span.text-right").text).to eq("19 Jul")
      end
    end

    it "carries the '%y suffix for a date-only value from another year" do
      travel_to(Time.zone.local(2026, 8, 1)) do
        rows = [ [ "Release", { "v" => "2025-07-19", "format" => "date" } ] ]
        node = render_inline(described_class.new(rows: rows))

        expect(node.at_css("span.text-right").text).to eq("19 Jul '25")
      end
    end

    it "never collapses a date-only value that IS today (still renders the date)" do
      travel_to(Time.zone.local(2026, 7, 19, 9, 0)) do
        rows = [ [ "Release", { "v" => "2026-07-19", "format" => "date" } ] ]
        node = render_inline(described_class.new(rows: rows))

        expect(node.at_css("span.text-right").text).to eq("19 Jul")
      end
    end

    it "no longer renders the old US-order, tz-ignorant %b %-d, %Y shape" do
      travel_to(Time.zone.local(2026, 8, 1)) do
        rows = [ [ "Release", { "v" => "2026-07-19", "format" => "date" } ] ]
        node = render_inline(described_class.new(rows: rows))

        expect(node.text).not_to include("Jul 19, 2026")
      end
    end

    it "no longer renders the old dd-mm-yyyy date-only shape" do
      travel_to(Time.zone.local(2026, 8, 1)) do
        rows = [ [ "Release", { "v" => "2026-07-19", "format" => "date" } ] ]
        node = render_inline(described_class.new(rows: rows))

        expect(node.text).not_to include("19-07-2026")
      end
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
