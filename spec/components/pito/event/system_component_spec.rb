# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::SystemComponent do
  # Item 18: messages render INSTANTLY — no typewriter controller / targets.
  describe "instant render — plain-text body" do
    subject(:node) { render_inline(described_class.new(payload: { body: "Hello world" })) }

    it "renders the body instantly with no typewriter wiring" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
      expect(node.css("[data-pito--typewriter-target]")).to be_empty
      expect(node.css("span.text-fg").text).to include("Hello world")
    end
  end

  describe "instant render — html body (html: true)" do
    subject(:node) { render_inline(described_class.new(payload: { body: "<b>bold</b>", html: true })) }

    it "renders the html card instantly with no typewriter wiring" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
      expect(node.css("[data-pito--typewriter-target]")).to be_empty
      expect(node.css("b").text).to eq("bold")
    end
  end

  describe "typewriter hook — html body, CONSUMED (no re-reveal on refresh/replace)" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "<b>card</b>", html: true,
        reply_handle: "h", reply_target: "game_detail", reply_consumed: true
      }))
    end

    it "does NOT mount the typewriter controller once consumed" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end

    it "still renders the html card content instantly" do
      expect(node.css("span.text-fg").first).not_to be_nil
    end
  end

  describe "typewriter hook — consumed (reply_consumed) re-render" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "All told, 2 videos.", reply_handle: "h", reply_target: "video_list", reply_consumed: true
      }))
    end

    it "renders statically (no typewriter controller) so a consumed re-render does not replay" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end

    it "still renders the body text instantly" do
      expect(node.text).to include("All told, 2 videos.")
    end
  end

  describe "typewriter hook — empty body" do
    subject(:node) { render_inline(described_class.new(payload: { body: nil })) }

    it "does NOT add the typewriter controller when body is nil" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end
  end

  describe "instant render — table_rows with plain-text body" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Result",
        table_rows: [ { key: "Status", value: "OK" } ]
      }))
    end

    it "renders the kv cells instantly with no typewriter targets" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
      expect(node.css("[data-pito--typewriter-target]")).to be_empty
      expect(node.text).to include("Status").and include("OK")
    end
  end

  describe "instant render — sections mode, plain-text body" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Sections body text",
        sections: [ { title: "Section 1", rows: [] } ]
      }))
    end

    it "renders the body + header instantly with no typewriter wiring" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
      expect(node.css("[data-pito--typewriter-target]")).to be_empty
      expect(node.text).to include("Sections body text").and include("Section 1")
    end
  end

  describe "instant render — sections mode, section rows" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Help",
        sections: [ {
          title: "Navigation",
          rows: [ { key: "ctrl+l", value: "focus input" } ]
        } ]
      }))
    end

    it "renders the section rows instantly with no prose targets" do
      expect(node.css("[data-pito--typewriter-target]")).to be_empty
      expect(node.text).to include("ctrl+l").and include("focus input")
    end
  end

  describe "instant render — sections mode, html body" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "<em>rich</em>",
        html: true,
        sections: [ { title: "Section 1", rows: [] } ]
      }))
    end

    it "renders the html sections card instantly with no typewriter wiring" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
      expect(node.css("[data-pito--typewriter-target]")).to be_empty
      expect(node.css("em").text).to eq("rich")
    end
  end

  describe "SystemFollowUpComponent (inherits system template via enhanced)" do
    it "renders a plain-text body instantly with no typewriter" do
      node = render_inline(Pito::Event::SystemFollowUpComponent.new(payload: { body: "Follow up text" }))
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
      expect(node.text).to include("Follow up text")
    end
  end

  # ── dom_id — generalized to reply_handle (follow-up engine) ─────────────────

  describe "dom_id — id on root Segment for follow-up-able messages" do
    let(:conversation) { Conversation.create! }
    let(:turn) { create(:turn, conversation:) }

    it "renders id='event_<id>' when payload has reply_handle present" do
      event = create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: { "reply_handle" => "beta-1234", "reply_target" => "game_list", "body" => "Pick a game" })
      node = render_inline(described_class.new(payload: event.payload.with_indifferent_access, event:))
      segment = node.css(".pito-segment").first
      expect(segment).not_to be_nil
      expect(segment["id"]).to eq("event_#{event.id}")
    end

    it "renders id='event_<id>' when payload has theme_diff: true (backward compat)" do
      diff_event = create(:event, conversation:, turn:, kind: "theme_diff", position: 2,
                          payload: { "theme_diff" => true, "phase" => "apply", "body" => "Done!" })
      node = render_inline(described_class.new(payload: diff_event.payload.with_indifferent_access, event: diff_event))
      segment = node.css(".pito-segment").first
      expect(segment["id"]).to eq("event_#{diff_event.id}")
    end

    it "renders id='event_<id>' when payload has anchor: true (internal machine-flow messages)" do
      anchor_event = create(:event, conversation:, turn:, kind: "system", position: 3,
                            payload: { "anchor" => true, "reply_target" => "channel_visit", "body" => "Visiting…" })
      node = render_inline(described_class.new(payload: anchor_event.payload.with_indifferent_access, event: anchor_event))
      segment = node.css(".pito-segment").first
      expect(segment).not_to be_nil
      expect(segment["id"]).to eq("event_#{anchor_event.id}")
    end

    it "does NOT render an id for a plain system message (no reply_handle, anchor, or theme_diff)" do
      plain_event = create(:event, conversation:, turn:, kind: "system", position: 4,
                           payload: { "body" => "Regular system message" })
      node = render_inline(described_class.new(payload: plain_event.payload.with_indifferent_access, event: plain_event))
      segment = node.css(".pito-segment").first
      expect(segment["id"]).to be_nil
    end

    it "does NOT render an id when event is nil even if payload has reply_handle" do
      node = render_inline(described_class.new(payload: { reply_handle: "beta-1234", body: "Pick" }, event: nil))
      segment = node.css(".pito-segment").first
      expect(segment["id"]).to be_nil
    end
  end

  # ── affordance rendered for follow-up-able system messages ───────────────────

  # ── html:true game messages render the standard timestamp ────────────────────

  describe "timestamp on html:true payload (game detail / enhanced messages)" do
    let(:conversation) { Conversation.create! }
    let(:turn) { create(:turn, conversation:) }

    it "renders the inline timestamp prefix (not a meta line) when event has created_at, even with no handle/channel" do
      event = create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: { "body" => "<b>game card</b>", "html" => true })
      node = render_inline(described_class.new(payload: event.payload.with_indifferent_access, event:))
      expect(node.css("span.pito-timestamp-prefix")).not_to be_empty
      expect(node.css(".pito-echo__meta")).to be_empty
    end

    it "does NOT render a meta line when event is nil and no handle/channel" do
      node = render_inline(described_class.new(payload: { body: "plain", html: true }, event: nil))
      expect(node.css(".pito-echo__meta")).to be_empty
    end

    # ── `--help` man-page bodies show the inline first-line timestamp ────────────
    it "places the timestamp prefix INSIDE the .pito-help-block (not orphaned above it)" do
      help_payload = Pito::MessageBuilder::CommandHelp.call(:platform)
      event = create(:event, conversation:, turn:, kind: "system", position: 2,
                     payload: help_payload)
      node = render_inline(described_class.new(payload: event.payload.with_indifferent_access, event:))

      help_block = node.css(".pito-help-block").first
      expect(help_block).to be_present
      # The timestamp prefix is a descendant of the help block, leading its first line.
      expect(help_block.css("span.pito-timestamp-prefix")).not_to be_empty
      # And it is not duplicated outside the block.
      expect(node.css("span.pito-timestamp-prefix").size).to eq(1)
    end
  end

  describe "table_rows with a third column (value2)" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Channels",
        table_rows: [ { key: "#1", value: "Alpha Tube", value2: "@alpha" } ]
      }))
    end

    it "uses a 3-track grid when any row carries value2" do
      grid = node.css("div.pito-data-grid").first
      expect(grid["data-cols"]).to eq("3")
    end

    it "renders the third-column value" do
      expect(node.text).to include("@alpha")
    end
  end

  # ── N-column :cells rows ──────────────────────────────────────────────────────

  describe "table_rows with :cells — 4-column row" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Stats",
        table_rows: [
          { cells: [
            { text: "Label",  class: "text-cyan whitespace-nowrap" },
            { text: "Value1", class: "text-fg-dim" },
            { text: "Value2", class: "text-fg-dim" },
            { text: "Extra",  class: "text-yellow" }
          ] }
        ]
      }))
    end

    it "uses a 4-track grid" do
      grid = node.css("div.pito-data-grid").first
      expect(grid["data-cols"]).to eq("4")
    end

    it "renders 4 spans inside the grid" do
      grid = node.css("div.pito-data-grid").first
      expect(grid.css("span").size).to eq(4)
    end

    it "renders the cell texts in order" do
      grid = node.css("div.pito-data-grid").first
      texts = grid.css("span").map(&:text)
      expect(texts).to eq(%w[Label Value1 Value2 Extra])
    end

    it "applies the supplied classes to each cell" do
      grid = node.css("div.pito-data-grid").first
      spans = grid.css("span")
      expect(spans[0]["class"]).to include("text-cyan")
      expect(spans[1]["class"]).to include("text-fg-dim")
      expect(spans[3]["class"]).to include("text-yellow")
    end
  end

  describe "list intro (html: true subject-shimmer body) + table_rows" do
    # Mirrors what the video/game/channel list builders now emit: an html intro
    # whose count + noun are wrapped in subject-shimmer spans, followed by the
    # table grid. Proves the html-flip reveals the shimmer AND keeps the table.
    subject(:node) do
      render_inline(described_class.new(payload: {
        "body" => Pito::Copy.render_html(
          "pito.copy.videos.list_intro",
          { count: 2, noun: "vids" },
          shimmer: [ :count, :noun ]
        ),
        "html" => true,
        "table_rows" => [
          { cells: [ { text: "#1", class: "text-fg" }, { text: "Alpha Video", class: "text-fg pito-cell-title" } ] },
          { cells: [ { text: "#2", class: "text-fg" }, { text: "Beta Video",  class: "text-fg pito-cell-title" } ] }
        ]
      }))
    end

    it "wraps the count and noun in subject-shimmer spans in the intro" do
      shimmered = node.css("span.pito-subject-shimmer").map(&:text)
      expect(shimmered).to include("2", "vids")
    end

    it "still renders the table grid with every row below the intro" do
      grid = node.css("div.pito-data-grid").first
      expect(grid).to be_present
      expect(grid.css("span").map(&:text)).to include("#1", "Alpha Video", "#2", "Beta Video")
    end
  end

  describe "table cell data: — chat-prefill attributes render on the cell span" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        "html" => true,
        "table_rows" => [
          { cells: [
            {
              text: "#7",
              class: "pito-reference-shimmer",
              data: Pito::Shimmer::TokenComponent.prefill_data("show vid #7", submit: true)
            },
            { text: "Alpha Video", class: "text-fg pito-cell-title" }
          ] }
        ]
      }))
    end

    it "wires the #id cell span as a click-to-submit chat-prefill token" do
      span = node.css("div.pito-data-grid span").find { |s| s.text == "#7" }
      expect(span).to be_present
      expect(span["data-controller"]).to eq("pito--chat-prefill")
      expect(span["data-action"]).to eq("click->pito--chat-prefill#fill")
      expect(span["data-pito--chat-prefill-text-value"]).to eq("show vid #7")
      expect(span["data-pito--chat-prefill-submit-value"]).to eq("true")
    end

    it "leaves cells without data: as plain spans (no controller)" do
      span = node.css("div.pito-data-grid span").find { |s| s.text == "Alpha Video" }
      expect(span["data-controller"]).to be_nil
    end
  end

  describe "table_rows legacy {key, value, value2} — 3-column back-compat" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Channels",
        table_rows: [ { key: "#1", value: "Alpha Tube", value2: "@alpha" } ]
      }))
    end

    it "uses a 3-track grid" do
      grid = node.css("div.pito-data-grid").first
      expect(grid["data-cols"]).to eq("3")
    end

    it "renders key span with text-cyan and whitespace-nowrap" do
      grid = node.css("div.pito-data-grid").first
      key_span = grid.css("span").first
      expect(key_span["class"]).to include("text-cyan")
      expect(key_span["class"]).to include("whitespace-nowrap")
      expect(key_span.text).to eq("#1")
    end

    it "renders value span with text-fg-dim" do
      grid = node.css("div.pito-data-grid").first
      value_span = grid.css("span")[1]
      expect(value_span["class"]).to include("text-fg-dim")
      expect(value_span.text).to eq("Alpha Tube")
    end

    it "renders value2 span with text-cyan and whitespace-nowrap" do
      grid = node.css("div.pito-data-grid").first
      value2_span = grid.css("span")[2]
      expect(value2_span["class"]).to include("text-cyan")
      expect(value2_span["class"]).to include("whitespace-nowrap")
      expect(value2_span.text).to eq("@alpha")
    end
  end

  describe "table_rows legacy {key, value} — 2-column back-compat" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Result",
        table_rows: [ { key: "Status", value: "OK" } ]
      }))
    end

    it "uses a 2-track grid" do
      grid = node.css("div.pito-data-grid").first
      expect(grid["data-cols"]).to eq("2")
    end

    it "does NOT use a 3-track grid" do
      grid = node.css("div.pito-data-grid").first
      expect(grid["data-cols"]).not_to eq("3")
    end
  end

  # ── table_heading — heading row in the kv-table grid ──────────────────────────

  describe "table_heading — present" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Results",
        table_heading: [ "A", "B", "C" ],
        table_rows: [ { cells: [
          { text: "v1", class: "text-fg" },
          { text: "v2", class: "text-fg" },
          { text: "v3", class: "text-fg" }
        ] } ]
      }))
    end

    it "renders 3 heading spans with text-fg-faded (not bold — bold is live-shimmer only)" do
      grid = node.css("div.pito-data-grid").first
      heading_spans = grid.css("span").first(3)
      expect(heading_spans.map(&:text)).to eq(%w[A B C])
      heading_spans.each do |span|
        expect(span["class"]).to include("text-fg-faded")
        expect(span["class"]).not_to include("font-bold")
      end
    end

    it "positions heading spans before the data-row spans" do
      grid = node.css("div.pito-data-grid").first
      all_spans = grid.css("span")
      expect(all_spans[0].text).to eq("A")
      expect(all_spans[1].text).to eq("B")
      expect(all_spans[2].text).to eq("C")
      expect(all_spans[3].text).to eq("v1")
    end

    it "heading spans do NOT carry a typewriter prose target" do
      grid = node.css("div.pito-data-grid").first
      heading_spans = grid.css("span").first(3)
      heading_spans.each do |span|
        expect(span["data-pito--typewriter-target"]).to be_nil
      end
    end

    it "does not shimmer headings unless shimmer_heading is set" do
      grid = node.css("div.pito-data-grid").first
      expect(grid.css("span.pito-reference-shimmer").first(3)).to be_empty
    end
  end

  describe "table_heading with shimmer_heading (headings stay PLAIN — owner 17.4)" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Results",
        table_heading: [ "A", "B", "C" ],
        shimmer_heading: true,
        table_rows: [ { cells: [
          { text: "v1", class: "text-fg" },
          { text: "v2", class: "text-fg" },
          { text: "v3", class: "text-fg" }
        ] } ]
      }))
    end

    it "keeps every heading PLAIN muted text even when shimmer_heading is set" do
      grid = node.css("div.pito-data-grid").first
      heading_spans = grid.css("span").first(3)
      heading_spans.each do |span|
        expect(span["class"]).to include("text-fg-faded")
        expect(span["class"]).not_to include("pito-reference-shimmer")
        expect(span["class"]).not_to match(/\bpito-shimmer-d\d+\b/)
        expect(span["class"]).not_to include("font-bold")
      end
    end

    it "uses a 3-track grid that accounts for the heading width" do
      grid = node.css("div.pito-data-grid").first
      expect(grid["data-cols"]).to eq("3")
    end
  end

  describe "table_heading with shimmer_heading on a CONSUMED list (reply_consumed: true)" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Results",
        table_heading: [ "A", "B", "C" ],
        shimmer_heading: true,
        reply_handle: "beta-1234",
        reply_target: "game_list",
        reply_consumed: true,
        table_rows: [ { cells: [
          { text: "v1", class: "text-fg" },
          { text: "v2", class: "text-fg" },
          { text: "v3", class: "text-fg" }
        ] } ]
      }))
    end

    it "heading spans have NO shimmer class when consumed" do
      grid = node.css("div.pito-data-grid").first
      heading_spans = grid.css("span").first(3)
      heading_spans.each do |span|
        expect(span["class"]).not_to include("pito-reference-shimmer")
        expect(span["class"]).not_to match(/\bpito-shimmer-d\d+\b/)
      end
    end

    it "heading spans are NOT bold when consumed" do
      grid = node.css("div.pito-data-grid").first
      heading_spans = grid.css("span").first(3)
      heading_spans.each do |span|
        expect(span["class"]).not_to include("font-bold")
      end
    end

    it "heading spans have text-fg-faded (muted) when consumed" do
      grid = node.css("div.pito-data-grid").first
      heading_spans = grid.css("span").first(3)
      heading_spans.each do |span|
        expect(span["class"]).to include("text-fg-faded")
      end
    end
  end

  # ── Uniform sortable-heading shimmer: fixed (#/Title/Game) AND added columns ──
  # Mirrors the real list/enhanced heading shape the builders emit:
  #   [ {text:"#",class:"text-right"}, "Title"/"Game", *heading_cells(cols) ]
  # where the added `with`-columns carry `pito-table-heading--added` (and an
  # optional `text-right`). J7: every sortable heading must shimmer alike when
  # live. J8/J15: every heading must drop to plain muted when consumed — the
  # added columns must NOT linger cyan via pito-table-heading--added.
  describe "sortable headings — uniform shimmer across fixed + added (LIVE)" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Results", html: true, shimmer_heading: true,
        table_heading: [
          { "text" => "#", "class" => "text-right" },
          "Game",
          { "text" => "Genre", "class" => "pito-table-heading--added" },
          { "text" => "Year",  "class" => "pito-table-heading--added text-right" }
        ],
        table_rows: [ { cells: [
          { text: "#1", class: "text-fg" }, { text: "Hades", class: "text-fg" },
          { text: "Roguelike", class: "text-fg-dim" }, { text: "2020", class: "text-fg-dim" }
        ] } ]
      }))
    end

    it "keeps EVERY heading (fixed #/Game AND added Genre/Year) PLAIN — no shimmer/bold (owner 17.4)" do
      grid = node.css("div.pito-data-grid").first
      grid.css("span").first(4).each do |span|
        expect(span["class"]).to include("text-fg-faded")
        expect(span["class"]).not_to include("pito-reference-shimmer")
        expect(span["class"]).not_to match(/\bpito-shimmer-d\d+\b/)
        expect(span["class"]).not_to include("font-bold")
      end
    end

    it "drops the legacy cyan pito-table-heading--added class (shimmer is the sole live affordance)" do
      grid = node.css("div.pito-data-grid").first
      grid.css("span").first(4).each do |span|
        expect(span["class"]).not_to include("pito-table-heading--added")
      end
    end

    it "preserves layout extras (text-right) on the # and Year headings" do
      grid = node.css("div.pito-data-grid").first
      spans = grid.css("span").first(4)
      expect(spans[0]["class"]).to include("text-right") # #
      expect(spans[3]["class"]).to include("text-right") # Year
    end
  end

  describe "sortable headings — ALL drop to plain muted when CONSUMED (J8/J15)" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Results", html: true, shimmer_heading: true,
        reply_handle: "beta-1234", reply_target: "game_list", reply_consumed: true,
        table_heading: [
          { "text" => "#", "class" => "text-right" },
          "Game",
          { "text" => "Genre", "class" => "pito-table-heading--added" },
          { "text" => "Year",  "class" => "pito-table-heading--added text-right" }
        ],
        table_rows: [ { cells: [
          { text: "#1", class: "text-fg" }, { text: "Hades", class: "text-fg" },
          { text: "Roguelike", class: "text-fg-dim" }, { text: "2020", class: "text-fg-dim" }
        ] } ]
      }))
    end

    it "removes shimmer, bold, AND the cyan pito-table-heading--added from EVERY heading" do
      grid = node.css("div.pito-data-grid").first
      grid.css("span").first(4).each do |span|
        expect(span["class"]).not_to include("pito-reference-shimmer")
        expect(span["class"]).not_to match(/\bpito-shimmer-d\d+\b/)
        expect(span["class"]).not_to include("font-bold")
        expect(span["class"]).not_to include("pito-table-heading--added")
      end
    end

    it "leaves every heading plain muted (text-fg-faded), layout extras intact" do
      grid = node.css("div.pito-data-grid").first
      spans = grid.css("span").first(4)
      spans.each { |span| expect(span["class"]).to include("text-fg-faded") }
      expect(spans[0]["class"]).to include("text-right") # #
      expect(spans[3]["class"]).to include("text-right") # Year
    end
  end

  describe "table_heading — absent (back-compat)" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Results",
        table_rows: [ { key: "Status", value: "OK" } ]
      }))
    end

    it "emits no heading spans (no text-fg-faded font-bold span in the grid)" do
      grid = node.css("div.pito-data-grid").first
      heading_spans = grid.css("span").select { |s| s["class"]&.include?("font-bold") }
      expect(heading_spans).to be_empty
    end
  end

  # ── wide table — 8 columns, no vertical-stack regression ─────────────────────

  describe "table_heading with 8 columns" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Wide table",
        table_heading: [ "#", "Game", "Developer", "Publisher", "Genre", "Release", "Year", "Platform" ],
        table_rows: [
          { cells: [
            { text: "1",    class: "text-cyan whitespace-nowrap" },
            { text: "Hades",         class: "text-fg" },
            { text: "Supergiant",    class: "text-fg-dim" },
            { text: "Supergiant",    class: "text-fg-dim" },
            { text: "Roguelike",     class: "text-fg-dim" },
            { text: "2020-09-17",    class: "text-fg-dim" },
            { text: "2020",          class: "text-fg-dim" },
            { text: "PC",            class: "text-fg-dim" }
          ] },
          { cells: [
            { text: "2",    class: "text-cyan whitespace-nowrap" },
            { text: "Celeste",       class: "text-fg" },
            { text: "Maddy Thorson", class: "text-fg-dim" },
            { text: "Maddy Thorson", class: "text-fg-dim" },
            { text: "Platformer",    class: "text-fg-dim" },
            { text: "2018-01-25",    class: "text-fg-dim" },
            { text: "2018",          class: "text-fg-dim" },
            { text: "Switch",        class: "text-fg-dim" }
          ] }
        ]
      }))
    end

    it "renders exactly one .pito-data-grid container" do
      grids = node.css("div.pito-data-grid")
      expect(grids.size).to eq(1)
    end

    it "sets data-cols=8 on the grid container" do
      grid = node.css("div.pito-data-grid").first
      expect(grid["data-cols"]).to eq("8")
    end

    it "renders 8 heading spans" do
      grid = node.css("div.pito-data-grid").first
      heading_spans = grid.css("span").first(8)
      expect(heading_spans.map(&:text)).to eq(%w[# Game Developer Publisher Genre Release Year Platform])
    end
  end

  # ── table_heading_cells — Hash entries (right-aligned headings) ───────────────

  describe "table_heading_cells — Hash entry merges extra class" do
    subject(:component) do
      described_class.new(payload: {
        body: "Results",
        table_heading: [ { "text" => "#", "class" => "text-right" }, "Game" ],
        table_rows: [ { cells: [
          { text: "1", class: "text-cyan" },
          { text: "Alpha", class: "text-fg" }
        ] } ]
      })
    end

    it "merges the extra class into the heading cell for a Hash entry" do
      cells = component.table_heading_cells
      expect(cells.first[:class]).to include("text-right")
      expect(cells.first[:class]).to include("text-fg-faded")
      expect(cells.first[:class]).not_to include("font-bold")
      expect(cells.first[:text]).to eq("#")
    end

    it "keeps the base class only for a String entry (muted, not bold)" do
      cells = component.table_heading_cells
      expect(cells[1][:class]).to eq("text-fg-faded whitespace-nowrap")
      expect(cells[1][:text]).to eq("Game")
    end
  end

  # ── data-fixed-trailing on the grid div ───────────────────────────────────────

  describe "data-fixed-trailing from payload" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "List",
        fixed_trailing: 2,
        table_heading: [ "#", "Game", "Release", "Year" ],
        table_rows: [ { cells: [
          { text: "#1", class: "text-cyan" },
          { text: "Alpha", class: "text-fg" },
          { text: "2024-01-01", class: "text-fg-dim text-right" },
          { text: "2024", class: "text-fg-dim text-right tabular-nums" }
        ] } ]
      }))
    end

    it "renders data-fixed-trailing on the pito-data-grid div" do
      grid = node.css("div.pito-data-grid").first
      expect(grid["data-fixed-trailing"]).to eq("2")
    end

    it "renders data-fixed-trailing=0 when not provided in payload" do
      node2 = render_inline(described_class.new(payload: {
        body: "Plain",
        table_rows: [ { key: "A", value: "B" } ]
      }))
      grid = node2.css("div.pito-data-grid").first
      expect(grid["data-fixed-trailing"]).to eq("0")
    end
  end

  # ── html cells in :cells rows ────────────────────────────────────────────────

  describe "table_rows with :cells — html: true cell renders raw (no typewriter target)" do
    let(:img_html) { '<span class="pito-platform-icons"><img class="pito-platform-icon" src="/platforms/playstation.svg" alt="PlayStation" title="PlayStation" loading="lazy"></span>' }

    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Games",
        table_rows: [
          { cells: [
            { text: "The Game",   class: "text-fg" },
            { text: img_html,     class: "text-fg-dim", html: true }
          ] }
        ]
      }))
    end

    it "renders the html cell without escaping (img tag is present)" do
      grid = node.css("div.pito-data-grid").first
      expect(grid.css("img.pito-platform-icon").first).not_to be_nil
    end

    it "renders the html cell instantly with no typewriter target" do
      grid = node.css("div.pito-data-grid").first
      html_span = grid.css("span").find { |s| s.css("img").any? }
      expect(html_span).not_to be_nil
      expect(html_span["data-pito--typewriter-target"]).to be_nil
    end

    it "renders the plain-text cell instantly with no typewriter target" do
      grid = node.css("div.pito-data-grid").first
      expect(grid.css("[data-pito--typewriter-target]")).to be_empty
      expect(grid.text).to include("The Game")
    end
  end

  describe "table_rows with :cells — html: false cell escapes (instant)" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Test",
        table_rows: [
          { cells: [
            { text: "<b>escaped</b>", class: "text-fg" }
          ] }
        ]
      }))
    end

    it "escapes the text (no b tag in the DOM)" do
      grid = node.css("div.pito-data-grid").first
      expect(grid.css("b").first).to be_nil
      expect(grid.text).to include("<b>escaped</b>")
    end

    it "renders the cell with no typewriter target" do
      grid = node.css("div.pito-data-grid").first
      expect(grid.css("[data-pito--typewriter-target]")).to be_empty
    end
  end

  describe "follow-up handle in the single meta line (no usage/affordance line)" do
    let(:conversation) { Conversation.create! }
    let(:turn) { create(:turn, conversation:) }

    # Since 0.9.0 Phase 5 the COMPONENT emits a meta SLOT (cache-stable); the
    # meta line itself — handle liveness included — is rendered into it at
    # serve time by Pito::Stream::EventRenderer. Component-level truth: the
    # slot is present; renderer-level truth: the #handle fills it while live.
    it "emits the meta slot for a follow-up-able message; the renderer fills in the #handle" do
      event = create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: {
                       "reply_handle" => "beta-1234",
                       "reply_target" => "game_detail",
                       "body" => "<b>game card</b>",
                       "html" => true
                     })
      node = render_inline(described_class.new(payload: event.payload.with_indifferent_access, event:))
      expect(node.css("[data-pito-meta-slot]")).to be_present

      html = Pito::Stream::EventRenderer.render(event)
      expect(html).to include("beta-1234")
      expect(html).not_to include("data-pito-meta-slot")
    end

    it "NEVER renders a separate usage/affordance line" do
      event = create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: {
                       "reply_handle" => "beta-1234",
                       "reply_target" => "game_detail",
                       "body" => "<b>card</b>", "html" => true
                     })
      node = render_inline(described_class.new(payload: event.payload.with_indifferent_access, event:))
      expect(node.css("div.mt-1.text-fg-faded")).to be_empty
      # no game usage tokens leak into the message
      expect(node.text).not_to include("resync")
      expect(node.text).not_to include("update ownership")
    end

    it "does NOT show the handle once the message is consumed" do
      event = create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: {
                       "reply_handle"   => "beta-1234",
                       "reply_target"   => "game_detail",
                       "reply_consumed" => true,
                       "body"           => "Consumed", "html" => true
                     })
      html = Pito::Stream::EventRenderer.render(event)
      expect(html).not_to include("beta-1234")
      expect(html).not_to include("data-pito-meta-slot")
    end

    it "serves the SAME cached fragment before and after consumption (only the slot fill differs)" do
      event = create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: {
                       "reply_handle" => "gamma-9",
                       "reply_target" => "game_detail",
                       "body" => "Stable", "html" => true
                     })
      live_key = Pito::Stream::FragmentCache.key(event)
      live_html = Pito::Stream::EventRenderer.render(event)

      event.update!(payload: event.payload.merge("reply_consumed" => true))
      expect(Pito::Stream::FragmentCache.key(event)).to eq(live_key) # no rotation
      consumed_html = Pito::Stream::EventRenderer.render(event)

      expect(live_html).to include("gamma-9")
      expect(consumed_html).not_to include("gamma-9")
    end
  end

  # A system message is ALWAYS transparent (left bar only). The payload[:surface]
  # "just changed by your reply" lift was removed (owner 2026-07-01) — replies/
  # follow-ups no longer elevate a message onto the surface background.
  describe "no reply-elevated surface background" do
    def content_style(payload)
      render_inline(described_class.new(payload:)).css(".pito-segment__content").first&.[]("style").to_s
    end

    it "stays transparent even when a stale payload still carries surface: true" do
      expect(content_style(body: "Re-sorted", surface: true)).not_to include("background")
    end

    it "stays transparent on a normal render" do
      expect(content_style(body: "First render")).not_to include("background")
    end
  end
end
