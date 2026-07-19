# frozen_string_literal: true

require "rails_helper"

# Ai::Projector — the anchored `#<handle> @ai <question>` reply's payload →
# text projection. A thin wrapper over Pito::Mcp::EventText (SYNTHETIC
# payloads, the shapes the real builders emit — same convention as
# spec/lib/pito/mcp/event_text_spec.rb — so the projection is pinned
# independently of any builder). Pure function: no DB writes, no mutation.
RSpec.describe Ai::Projector do
  def event(kind: :system, payload:)
    instance_double(Event, kind:, payload:)
  end

  describe "a table_rows list payload" do
    let(:payload) do
      {
        "body"          => "<p>2 vids</p>",
        "table_heading" => [ { "text" => "#", "class" => "text-right" }, "Title", "Views" ],
        "table_rows"    => [
          { cells: [ { text: "#12" }, { text: "Cool Vid" }, { text: "<span>1,234</span>", html: true } ] },
          { cells: [ { text: "#7" },  { text: "Solo" },     { text: "9" } ] }
        ]
      }
    end

    it "projects the de-HTML'd intro above a markdown table — chrome-free (no reply_handle/css/data attrs)" do
      text = described_class.call(event(payload:))

      expect(text).to eq(<<~TEXT.strip)
        2 vids

        | # | Title | Views |
        | --- | --- | --- |
        | #12 | Cool Vid | 1,234 |
        | #7 | Solo | 9 |
      TEXT
    end
  end

  describe "a detail-card payload (body-only HTML, e.g. game/video/channel detail)" do
    let(:payload) do
      {
        "body"    => "<div><h2>Lies of P</h2><p>Genre: Action RPG</p><p>Price: 59.99</p></div>",
        "html"    => true,
        "game_id" => 42,
        # Chrome that must NEVER leak into the projection.
        "reply_handle" => "delta-4823",
        "reply_target" => "game_detail"
      }
    end

    it "projects the HTML stripped to plain text lines, excluding every chrome key" do
      text = described_class.call(event(payload:))

      expect(text).to eq("Lies of P\nGenre: Action RPG\nPrice: 59.99")
      expect(text).not_to include("delta-4823", "game_detail", "<div>", "<h2>")
    end
  end

  describe "an analyze payload (body-only rendered scaffold, e.g. numbers/breakdowns)" do
    let(:payload) do
      {
        "body" => "<div><h3>My Channel — last 7 days</h3><p>Views: 1,204</p></div>",
        "html" => true,
        "analyze" => { "role" => "system", "with" => [], "without" => [] },
        "reply_handle" => "beta-1111"
      }
    end

    it "projects the HTML stripped to plain text, excluding the analyze marker and reply chrome" do
      text = described_class.call(event(payload:))

      expect(text).to eq("My Channel — last 7 days\nViews: 1,204")
      expect(text).not_to include("beta-1111")
    end
  end

  describe "the originating command" do
    it "appends a trailing line when origin_tool is stamped" do
      payload = { "body" => "<p>hello</p>", "origin_tool" => "show" }
      text    = described_class.call(event(payload:))

      expect(text).to eq("hello\n\n(from the `show` command)")
    end

    it "omits the trailing line when origin_tool is absent" do
      payload = { "body" => "<p>hello</p>" }
      text    = described_class.call(event(payload:))

      expect(text).to eq("hello")
    end
  end

  describe "an :ai answer's payload (blocks, not table_rows/body/text)" do
    it "projects to nil — a deliberate no-op, not a gap (Ai::History's must_include_turn already carries the exchange)" do
      payload = {
        "status" => "done", "blocks" => [ { "type" => "text", "text" => "here's what I found" } ],
        "reply_handle" => "ai-9001"
      }
      expect(described_class.call(event(kind: :ai, payload:))).to be_nil
    end
  end

  describe "edge cases" do
    it "returns nil for a nil event" do
      expect(described_class.call(nil)).to be_nil
    end

    it "returns nil when the payload projects to nothing (no text/table/body/etc.)" do
      expect(described_class.call(event(payload: { "reply_handle" => "x-0001" }))).to be_nil
    end
  end
end
