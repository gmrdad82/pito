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

    it "strips emphasis, backticks, and leading # headers" do
      node = render_block(block)
      expect(node.text).not_to include("**")
      expect(node.text).not_to include("`")
      expect(node.text).not_to include("# Heading")
      expect(node.text).to include("bold and code")
      expect(node.text).to include("Heading")
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

    context "viz=heatmap with 7 values" do
      let(:block) { { "type" => "chart", "viz" => "heatmap", "values" => [ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0 ] } }

      it "renders 7 weekday bars" do
        node = render_block(block)
        expect(node.css(".pito-metric--heatmap")).not_to be_empty
        expect(node.css(".pito-heatmap__bar").size).to eq(7)
      end
    end

    context "viz=area" do
      let(:block) { { "type" => "chart", "viz" => "area", "series" => [ 1.0, 2.0, 3.0 ] } }

      it "renders via the sparkline engine" do
        node = render_block(block)
        expect(node.css(".pito-metric--sparkline")).not_to be_empty
        expect(node.css(".pito-metric__row").size).to eq(2)
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
      { "type" => "ttb", "hours" => { "main" => 30.0, "extras" => 60.0, "completionist" => 100.0 } }
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
