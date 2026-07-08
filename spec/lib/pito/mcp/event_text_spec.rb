# frozen_string_literal: true

require "rails_helper"

# Contract for Pito::Mcp::EventText — the markdown/plain-text projection of a
# read-verb event array. Exercised with SYNTHETIC payloads (the shapes the real
# builders emit, per the catalog) so the projection is pinned independently of any
# builder. A pure function: no DB, no persistence.
RSpec.describe Pito::Mcp::EventText do
  def project(payload)
    described_class.call([ { payload: payload } ])
  end

  describe "plain text (`text`)" do
    it "passes an already-rendered copy string through verbatim" do
      expect(project("text" => "No analytics yet.")).to eq("No analytics yet.")
    end
  end

  describe "markdown table (`table_rows`)" do
    let(:payload) do
      {
        "body"          => "<p>3 vids</p>",
        "table_heading" => [ { "text" => "#", "class" => "text-right" }, "Title", "Views" ],
        "table_rows"    => [
          { cells: [ { text: "#12" }, { text: "Cool Vid" }, { text: "<span>1,234</span>", html: true } ] },
          { cells: [ { text: "#7" },  { text: "Solo" } ] }
        ]
      }
    end

    subject(:text) { project(payload) }

    it "renders a GitHub-markdown table with a header divider" do
      expect(text).to include("| # | Title | Views |", "| --- | --- | --- |")
    end

    it "prepends the de-HTML'd intro body above the table" do
      expect(text).to start_with("3 vids\n\n|")
    end

    it "inline-strips HTML inside a cell marked html: true" do
      expect(text).to include("| #12 | Cool Vid | 1,234 |")
    end

    it "pads a ragged row to the table width" do
      expect(text).to include("| #7 | Solo |  |")
    end

    it "escapes a literal pipe in cell text" do
      payload[:table_rows] = [ { cells: [ { text: "#1" }, { text: "A | B" } ] } ]
      expect(project(payload)).to include('A \| B')
    end
  end

  describe "breakdown lists (`bars`)" do
    let(:payload) do
      {
        "bars"         => { "geography" => [ { "key" => "US", "pct" => 62.0 }, { "key" => "UK", "pct" => 7.3 } ],
                            "devices"    => [ { "key" => "Mobile", "pct" => 55.0 } ] },
        "bar_captions" => { "geography" => "<b>Top regions</b>" }
      }
    end

    subject(:text) { project(payload) }

    it "labels each breakdown metric (humanized, bold)" do
      expect(text).to include("**geography**", "**devices**")
    end

    it "lists each slice as `key: pct%`, integers without a decimal" do
      expect(text).to include("- US: 62%", "- Mobile: 55%")
    end

    it "keeps one decimal for a non-integer percentage" do
      expect(text).to include("- UK: 7.3%")
    end

    it "de-HTML's a bar caption when present" do
      expect(text).to include("Top regions")
      expect(text).not_to include("<b>")
    end
  end

  describe "games grid (`games`)" do
    it "renders each game as an id/title/vids bullet" do
      text = project("games" => [ { "id" => 5, "title" => "Celeste", "vids" => 4 },
                                  { "id" => 9, "title" => "Hades", "vids" => 12 } ])
      expect(text).to eq("- #5 Celeste (4 vids)\n- #9 Hades (12 vids)")
    end
  end

  describe "computed analytics scalars (`metrics`, filled by the Executor)" do
    it "renders each metric as a humanized `label: value` bullet" do
      text = project("metrics" => { "views" => 1234, "watched_hours" => 56.7 })
      expect(text).to eq("- views: 1234\n- watched hours: 56.7")
    end

    it "accepts an ordered Array of [label, value] pairs" do
      text = project("metrics" => [ [ "subs_net", "+42" ], [ "ctr", "4.1%" ] ])
      expect(text).to eq("- subs net: +42\n- ctr: 4.1%")
    end
  end

  describe "HTML-only cards (`body`) — detail / shinies / similar" do
    it "de-HTML's block elements into newlines and decodes entities" do
      body = '<div class="card"><div>Title: Hollow &amp; Knight</div><div>Platform: PC</div></div>'
      expect(project("body" => body, "html" => true, "game_id" => 3))
        .to eq("Title: Hollow & Knight\nPlatform: PC")
    end

    it "turns <br> into a newline" do
      expect(project("body" => "one<br>two")).to eq("one\ntwo")
    end

    it "collapses runs of whitespace and blank lines" do
      expect(project("body" => "<p>a</p>\n\n\n<p>   b   </p>")).to eq("a\nb")
    end

    it "returns empty string for a blank body" do
      expect(project("body" => "")).to eq("")
    end
  end

  describe "error events (`message_key`)" do
    it "renders the copy key into readable text" do
      allow(Pito::Copy).to receive(:render).with("pito.copy.x.y", {}).and_return("Something went wrong.")
      expect(project("message_key" => "pito.copy.x.y", "message_args" => {})).to eq("Something went wrong.")
    end

    it "passes symbolized message_args to Copy.render" do
      allow(Pito::Copy).to receive(:render).and_return("no such game")
      project("message_key" => "pito.copy.z", "message_args" => { "id" => 9 })
      expect(Pito::Copy).to have_received(:render).with("pito.copy.z", { id: 9 })
    end

    it "falls back to the bare key when rendering raises" do
      allow(Pito::Copy).to receive(:render).and_raise(StandardError)
      expect(project("message_key" => "pito.copy.retired")).to eq("pito.copy.retired")
    end
  end

  describe "structure over kind" do
    it "reads payload keys with indifferent access (symbol OR string)" do
      symbol_keyed = project(text: "sym works")
      string_keyed = project("text" => "sym works")
      expect(symbol_keyed).to eq(string_keyed).and eq("sym works")
    end

    it "prefers structured table output even when a body is also present" do
      text = project("body" => "<p>intro</p>",
                     "table_rows" => [ { cells: [ { text: "x" } ] } ])
      expect(text).to include("intro").and include("| x |")
    end
  end

  describe ".call over an events array" do
    it "joins multiple event projections with a blank line, dropping empties" do
      events = [
        { payload: { "text" => "first" } },
        { payload: {} },                          # empty → dropped
        { payload: { "text" => "second" } }
      ]
      expect(described_class.call(events)).to eq("first\n\nsecond")
    end

    it "reads the payload under a string `payload` key too" do
      expect(described_class.call([ { "payload" => { "text" => "hi" } } ])).to eq("hi")
    end

    it "is empty for an empty events array" do
      expect(described_class.call([])).to eq("")
    end

    it "tolerates a nil payload" do
      expect(described_class.call([ { payload: nil } ])).to eq("")
    end
  end
end
