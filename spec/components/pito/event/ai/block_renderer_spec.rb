# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::Ai::BlockRenderer, type: :component do
  # Renders the mapped component and returns the Capybara::Node for a
  # normalized string-keyed block, exactly as Ai::Blocks would emit it.
  def render_block(block)
    render_inline(described_class.component_for(block))
  end

  describe "text" do
    let(:block) do
      {
        "type" => "text",
        "text" => "Hello <script>alert(1)</script>\n**bold** and `code`\n# Heading\nSecond line"
      }
    end

    it "maps to TextBlockComponent" do
      expect(described_class.component_for(block)).to be_a(Pito::Event::Ai::TextBlockComponent)
    end

    it "escapes HTML" do
      node = render_block(block)
      expect(node.css("script")).to be_empty
      expect(node.to_html).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
    end

    it "preserves newlines under the whitespace-pre-wrap class" do
      node = render_block(block)
      expect(node.css("div.whitespace-pre-wrap")).not_to be_empty
      expect(node.text).to include("\n")
    end

    it "strips backticks and leading # headers; emphasis renders as styling" do
      node = render_block(block)
      expect(node.text).not_to include("**")
      expect(node.text).not_to include("`")
      expect(node.text).not_to include("# Heading")
      expect(node.css("span.font-bold").text).to eq("bold")
      expect(node.text).to include("bold and code")
      expect(node.text).to include("Heading")
    end

    it "renders the declared inline styling — bold, italic, allowed colors — as spans" do
      node = render_block({ "type" => "text",
                            "text" => "**bold** and *slanted* and [cyan]id[/cyan] and [red]bad[/red]" })

      expect(node.css("span.font-bold").text).to eq("bold")
      expect(node.css("span.italic").text).to eq("slanted")
      expect(node.css("span.text-cyan").text).to eq("id")
      expect(node.css("span.text-red").text).to eq("bad")
      expect(node.text).not_to include("**", "[cyan]")
    end

    it "renders semantic [subject]/[ref] tokens in the house shimmer/token style" do
      node = render_block({ "type" => "text",
                            "text" => "Play [subject]Elden Ring[/subject] — see [ref]#12[/ref]." })

      subject = node.css("span.pito-subject-shimmer")
      expect(subject.text).to eq("Elden Ring")
      token = node.css("span.pito-reference-shimmer")
      expect(token.text).to eq("#12")
      expect(node.text).not_to include("[subject]", "[ref]")
    end

    it "unwraps a color tag outside the allowed palette to plain text" do
      node = render_block({ "type" => "text", "text" => "[purple]nope[/purple]" })
      expect(node.text).to include("nope")
      expect(node.text).not_to include("[purple]")
      expect(node.css("span[class*=purple]")).to be_empty
    end

    it "escapes HTML inside styled spans" do
      node = render_block({ "type" => "text", "text" => "**<script>x</script>**" })
      expect(node.css("script")).to be_empty
      expect(node.css("span.font-bold").text).to eq("<script>x</script>")
    end

    it "renders the timestamp prefix INLINE inside the text flow when given one" do
      node = render_inline(described_class.component_for(block, timestamp: Time.current.change(hour: 5, min: 22)))
      prefix = node.css("div.whitespace-pre-wrap .pito-timestamp-prefix")
      expect(prefix).not_to be_empty
      expect(node.text).to start_with("05:22 Hello")
    end
  end

  describe "kv_table" do
    let(:block) { { "type" => "kv_table", "rows" => [ [ "Rating", "84" ], [ "Genre", "RPG" ] ] } }

    it "maps to KvTableBlockComponent" do
      expect(described_class.component_for(block)).to be_a(Pito::Event::Ai::KvTableBlockComponent)
    end

    it "renders one KeyValueRow per row, each with a colon-suffixed key" do
      node = render_block(block)
      expect(node.text).to include("Rating:")
      expect(node.text).to include("Genre:")
      expect(node.text).to include("84")
      expect(node.text).to include("RPG")
    end
  end

  describe "table" do
    it "maps to TableBlockComponent" do
      block = { "type" => "table", "header" => [ "Col A", "Col B" ], "rows" => [ [ "1", "2" ] ] }
      expect(described_class.component_for(block)).to be_a(Pito::Event::Ai::TableBlockComponent)
    end

    it "renders the DataGrid with header cells and body rows" do
      block = { "type" => "table", "header" => [ "Col A", "Col B" ], "rows" => [ [ "1", "2" ] ] }
      node = render_block(block)

      cells = node.css(".pito-data-grid > span")
      expect(cells.map(&:text)).to eq([ "Col A", "Col B", "1", "2" ])
    end

    it "right-aligns numeric columns — header included — and leaves prose columns alone" do
      block = { "type" => "table", "header" => [ "Channel", "Subs", "Views" ],
                "rows" => [ [ "Main", "2.2K", "7,709" ], [ "Hard", "3", "93%" ] ] }
      node  = render_block(block)
      cells = node.css(".pito-data-grid > span")

      aligned = cells.select { |c| c["class"].to_s.include?("text-right") }.map(&:text)
      expect(aligned).to contain_exactly("Subs", "Views", "2.2K", "7,709", "3", "93%")
    end
  end

  describe "media" do
    context "with a real created game carrying no cover art" do
      let(:game) { create(:game) }
      let(:block) { { "type" => "media", "entity" => "game", "id" => game.id, "variant" => "cover" } }

      it "maps to MediaBlockComponent" do
        expect(described_class.component_for(block)).to be_a(Pito::Event::Ai::MediaBlockComponent)
      end

      it "renders the click-to-sync placeholder" do
        node = render_block(block)
        trigger = node.css("[data-pito--chat-prefill-text-value]").first
        expect(trigger).to be_present
        expect(trigger["data-pito--chat-prefill-text-value"]).to eq("sync game ##{game.id}")
      end
    end

    context "with a nonexistent id" do
      let(:block) { { "type" => "media", "entity" => "game", "id" => 999_999, "variant" => "cover" } }

      it "has render? false and renders empty" do
        component = described_class.component_for(block)
        expect(component.render?).to be false
        expect(render_block(block).to_html.strip).to eq("")
      end
    end
  end

  describe "sparkline" do
    let(:block) { { "type" => "sparkline", "series" => [ 1.0, 2.0, 3.0 ] } }

    it "maps to VizBlockComponent" do
      expect(described_class.component_for(block)).to be_a(Pito::Event::Ai::VizBlockComponent)
    end

    it "renders the braille sparkline rows" do
      node = render_block(block)
      expect(node.css(".pito-metric--sparkline")).not_to be_empty
      expect(node.css(".pito-metric__row").size).to eq(2)
    end

    it "renders the label line when a label is present" do
      labelled = block.merge("label" => "Weekly Views")
      node = render_block(labelled)
      expect(node.css("div.text-fg-dim").first.text).to eq("Weekly Views")
    end
  end

  describe "chart" do
    it "maps to VizBlockComponent" do
      block = { "type" => "chart", "viz" => "bar", "bars" => [ { "label" => "Solo", "pct" => 60.0 } ] }
      expect(described_class.component_for(block)).to be_a(Pito::Event::Ai::VizBlockComponent)
    end

    context "viz=bar with one bar" do
      let(:block) do
        { "type" => "chart", "viz" => "bar", "bars" => [ { "label" => "Solo", "pct" => 60.0, "value_label" => "60%" } ] }
      end

      it "renders the bar visualizer output" do
        node = render_block(block)
        expect(node.css(".pito-metric--bar")).not_to be_empty
        expect(node.css(".pito-bar-fill")).not_to be_empty
        expect(node.css(".pito-metric__blegend-item").text).to include("Solo", "60%")
      end
    end

    context "viz=bar bucket colors" do
      it "assigns each bucket its own hue from the house ramp" do
        block = { "type" => "chart", "viz" => "bar", "data" => { "bars" => [
          { "label" => "A", "pct" => 50.0 }, { "label" => "B", "pct" => 30.0 }, { "label" => "C", "pct" => 20.0 }
        ] } }
        html = render_inline(described_class.component_for(
          Ai::Blocks.normalize([ block ], conversation: nil).first
        )).to_html
        expect(html).to include("var(--accent-green)", "var(--accent-cyan)", "var(--brand-pito)")
      end
    end

    context "viz=heatmap with 7 values and no labels" do
      let(:block) { { "type" => "chart", "viz" => "heatmap", "values" => [ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0 ] } }

      it "renders 7 bars with the weekday preset ticks" do
        node = render_block(block)
        expect(node.css(".pito-metric--heatmap")).not_to be_empty
        expect(node.css(".pito-heatmap__bar").size).to eq(7)
        expect(node.css(".pito-heatmap__xticks span").map(&:text)).to eq(%w[Mo Tu We Th Fr Sa Su])
      end
    end

    context "viz=heatmap with labelled values" do
      let(:block) do
        { "type" => "chart", "viz" => "heatmap",
          "values" => [ 1.0, 2.0, 3.0 ], "labels" => %w[Q1 Q2 Q3] }
      end

      it "renders one bar per value with the labels as x-ticks" do
        node = render_block(block)
        expect(node.css(".pito-heatmap__bar").size).to eq(3)
        expect(node.css(".pito-heatmap__xticks span").map(&:text)).to eq(%w[Q1 Q2 Q3])
      end
    end

    context "viz=heart" do
      let(:block) do
        { "type" => "chart", "viz" => "heart", "score" => 84, "likes" => 120, "dislikes" => 6 }
      end

      it "renders one red braille heart with the likes/dislikes legend" do
        node = render_block(block)
        expect(node.to_html).to include("pito-metric")
        expect(node.text).to include("120")
        expect(node.text).to include("6")
      end
    end

    context "viz=area" do
      let(:block) do
        { "type" => "chart", "viz" => "area", "series" => [ 1.0, 2.0, 3.0 ],
          "target" => 2.0, "format" => "count" }
      end

      it "renders the full ticked Area chart via its generic kwargs" do
        node = render_block(block)
        expect(node.to_html).to include("pito-metric")
        # The full chart carries y-tick VALUES and an x-axis row — the compact
        # sparkline has neither.
        expect(node.css(".pito-metric__row").size).to be > 2
        expect(node.text).to include("1") # day-index x fallback (no dates given)
      end
    end
  end

  describe "score" do
    let(:block) { { "type" => "score", "value" => 84, "label" => "People" } }

    it "maps to VizBlockComponent" do
      expect(described_class.component_for(block)).to be_a(Pito::Event::Ai::VizBlockComponent)
    end

    it "renders the ScoreBar output with the label" do
      node = render_block(block)
      expect(node.css(".pito-score-bar")).not_to be_empty
      expect(node.css(".pito-score-bar__label").text).to eq("People")
      expect(node.css(".pito-score-bar__value").text).to eq("84")
    end

    it "does not render a separate VizBlockComponent label line (ScoreBar carries its own)" do
      node = render_block(block)
      expect(node.css("div.text-fg-dim")).to be_empty
    end
  end

  describe "ttb" do
    let(:block) do
      { "type" => "ttb",
        "levels" => [
          { "label" => "level 1", "hours" => 30.0 },
          { "label" => "level 2", "hours" => 60.0 },
          { "label" => "level 3", "hours" => 100.0 }
        ],
        "current" => { "label" => "so far", "hours" => 12.0 } }
    end

    it "maps to VizBlockComponent" do
      expect(described_class.component_for(block)).to be_a(Pito::Event::Ai::VizBlockComponent)
    end

    it "renders the TimeToBeat gauge" do
      node = render_block(block)
      expect(node.css(".pito-ttb")).not_to be_empty
      expect(node.css(".pito-ttb__value--pillar").size).to eq(3)
    end
  end

  describe "suggestion" do
    let(:block) { { "type" => "suggestion", "command" => "list games", "note" => "worth a look" } }

    it "maps to SuggestionBlockComponent" do
      expect(described_class.component_for(block)).to be_a(Pito::Event::Ai::SuggestionBlockComponent)
    end

    it "renders the >-prefixed command, the note, and the copy widget" do
      node = render_block(block)
      expect(node.css("span.text-fg-faded").text).to eq(">")
      expect(node.text).to include("list games")
      expect(node.text).to include("worth a look")
      expect(node.css("[data-controller='pito--clipboard']")).not_to be_empty
    end
  end

  describe "unknown type" do
    let(:block) { { "type" => "mystery", "weird" => true } }

    it "falls back to a JSON-in-text block" do
      component = described_class.component_for(block)
      expect(component).to be_a(Pito::Event::Ai::TextBlockComponent)

      node = render_block(block)
      expect(node.text).to include(JSON.generate(block))
    end
  end
end
