# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::SystemComponent do
  describe "typewriter hook — plain-text body" do
    subject(:node) { render_inline(described_class.new(payload: { body: "Hello world" })) }

    it "wraps content in a div with data-controller='pito--typewriter'" do
      wrapper = node.css("div[data-controller~='pito--typewriter']").first
      expect(wrapper).not_to be_nil
    end

    it "sets data-pito--typewriter-target='body' on the body span inside the wrapper" do
      span = node.css("[data-controller~='pito--typewriter'] span[data-pito--typewriter-target='body']").first
      expect(span).not_to be_nil
    end

    it "includes the body text in the body span" do
      span = node.css("span.text-fg[data-pito--typewriter-target='body']").first
      expect(span).not_to be_nil
      expect(span.text).to include("Hello world")
    end
  end

  describe "typewriter hook — html body (html: true)" do
    subject(:node) { render_inline(described_class.new(payload: { body: "<b>bold</b>", html: true })) }

    it "does NOT add the typewriter controller when body is html" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end

    it "renders the raw html in a plain text-fg span" do
      span = node.css("span.text-fg").first
      expect(span).not_to be_nil
    end
  end

  describe "typewriter hook — empty body" do
    subject(:node) { render_inline(described_class.new(payload: { body: nil })) }

    it "does NOT add the typewriter controller when body is nil" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end
  end

  describe "typewriter hook — table_rows with plain-text body" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Result",
        table_rows: [ { key: "Status", value: "OK" } ]
      }))
    end

    it "includes kv key span tagged as prose target inside the typewriter wrapper" do
      wrapper = node.css("div[data-controller~='pito--typewriter']").first
      expect(wrapper).not_to be_nil
      key_span = wrapper.css("span[data-pito--typewriter-target='prose']").first
      expect(key_span).not_to be_nil
    end

    it "key and value spans are both tagged as prose targets" do
      prose_spans = node.css("span[data-pito--typewriter-target='prose']")
      texts = prose_spans.map(&:text)
      expect(texts).to include("Status")
      expect(texts).to include("OK")
    end
  end

  describe "sections mode — plain-text body" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Sections body text",
        sections: [ { title: "Section 1", rows: [] } ]
      }))
    end

    it "adds pito--typewriter controller to the prose wrapper div in sections mode" do
      wrapper = node.css("div[data-controller~='pito--typewriter']").first
      expect(wrapper).not_to be_nil
      span = wrapper.css("span[data-pito--typewriter-target='body']").first
      expect(span).not_to be_nil
      expect(span.text).to include("Sections body text")
    end

    it "tags section header as a prose target" do
      header = node.css("[data-pito--typewriter-target='prose']").first
      expect(header).not_to be_nil
    end
  end

  describe "sections mode — section rows tagged as prose targets" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Help",
        sections: [ {
          title: "Navigation",
          rows: [ { key: "ctrl+l", value: "focus input" } ]
        } ]
      }))
    end

    it "tags section row key span as prose target" do
      key_span = node.css("span[data-pito--typewriter-target='prose']").first
      expect(key_span).not_to be_nil
      expect(key_span.text).to eq("ctrl+l")
    end

    it "tags section row value span as prose target" do
      value_span = node.css("span[data-pito--typewriter-target='prose']").last
      expect(value_span).not_to be_nil
      expect(value_span.text).to eq("focus input")
    end
  end

  describe "sections mode — html body" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "<em>rich</em>",
        html: true,
        sections: [ { title: "Section 1", rows: [] } ]
      }))
    end

    it "does NOT add typewriter controller in sections mode when html" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end
  end

  describe "SystemFollowUpComponent (inherits system template via enhanced)" do
    it "renders pito--typewriter on plain-text body" do
      node = render_inline(Pito::Event::SystemFollowUpComponent.new(payload: { body: "Follow up text" }))
      expect(node.css("[data-controller~='pito--typewriter']")).not_to be_empty
    end
  end

  # ── T15.4: dom_id — generalized to reply_handle (follow-up engine) ──────────

  describe "dom_id — id on root Segment for follow-up-able messages" do
    let(:conversation) { Conversation.create! }
    let(:turn) { create(:turn, conversation:) }

    it "renders id='event_<id>' when payload has reply_handle present" do
      event = create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: { "reply_handle" => "beta-1234", "reply_target" => "theme_list", "body" => "Pick a theme" })
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

    it "does NOT render an id for a plain system message (no reply_handle or theme_diff)" do
      plain_event = create(:event, conversation:, turn:, kind: "system", position: 3,
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

  # ── T15.3: affordance rendered for follow-up-able system messages ─────────────

  # ── T16.10: html:true game messages render the standard timestamp ────────────

  describe "timestamp on html:true payload (game detail / enhanced messages)" do
    let(:conversation) { Conversation.create! }
    let(:turn) { create(:turn, conversation:) }

    it "renders the meta line (with timestamp) when event has created_at, even with no handle/channel" do
      event = create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: { "body" => "<b>game card</b>", "html" => true })
      node = render_inline(described_class.new(payload: event.payload.with_indifferent_access, event:))
      expect(node.css(".pito-echo__meta").first).not_to be_nil
    end

    it "does NOT render a meta line when event is nil and no handle/channel" do
      node = render_inline(described_class.new(payload: { body: "plain", html: true }, event: nil))
      expect(node.css(".pito-echo__meta")).to be_empty
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

    it "renders 3 heading spans with text-fg-faded and font-bold" do
      grid = node.css("div.pito-data-grid").first
      heading_spans = grid.css("span").first(3)
      expect(heading_spans.map(&:text)).to eq(%w[A B C])
      heading_spans.each do |span|
        expect(span["class"]).to include("text-fg-faded")
        expect(span["class"]).to include("font-bold")
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

    it "uses a 3-track grid that accounts for the heading width" do
      grid = node.css("div.pito-data-grid").first
      expect(grid["data-cols"]).to eq("3")
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

  # ── T3.7: wide table — 8 columns, no vertical-stack regression ───────────────

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
      expect(cells.first[:class]).to include("font-bold")
      expect(cells.first[:text]).to eq("#")
    end

    it "keeps the base class only for a String entry" do
      cells = component.table_heading_cells
      expect(cells[1][:class]).to eq("text-fg-faded font-bold whitespace-nowrap")
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

    it "does NOT add a typewriter prose target to the html cell span" do
      grid = node.css("div.pito-data-grid").first
      spans = grid.css("span")
      html_span = spans.find { |s| s.css("img").any? }
      expect(html_span).not_to be_nil
      expect(html_span["data-pito--typewriter-target"]).to be_nil
    end

    it "still adds typewriter prose target to the plain-text cell span" do
      grid = node.css("div.pito-data-grid").first
      text_span = grid.css("span[data-pito--typewriter-target='prose']").first
      expect(text_span).not_to be_nil
      expect(text_span.text).to include("The Game")
    end
  end

  describe "table_rows with :cells — html: false cell escapes and keeps typewriter target" do
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

    it "keeps the typewriter prose target on the span" do
      grid = node.css("div.pito-data-grid").first
      span = grid.css("span[data-pito--typewriter-target='prose']").first
      expect(span).not_to be_nil
    end
  end

  describe "follow-up handle in the single meta line (no usage/affordance line)" do
    let(:conversation) { Conversation.create! }
    let(:turn) { create(:turn, conversation:) }

    it "shows the #handle in the meta line for a follow-up-able message" do
      event = create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: {
                       "reply_handle" => "beta-1234",
                       "reply_target" => "game_detail",
                       "body" => "<b>game card</b>",
                       "html" => true
                     })
      node = render_inline(described_class.new(payload: event.payload.with_indifferent_access, event:))
      expect(node.css(".pito-echo__meta").text).to include("beta-1234")
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
      node = render_inline(described_class.new(payload: event.payload.with_indifferent_access, event:))
      expect(node.css(".pito-echo__meta").text).not_to include("beta-1234")
    end
  end
end
