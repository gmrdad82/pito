# frozen_string_literal: true

require "rails_helper"

# The AI content ontology loader — config/pito/content.yml is the single
# declaration of what the model may compose; this guard keeps it valid and
# keeps the generated tool document faithful to it (the add-a-block proof:
# a new block type is a YAML entry + support code, never a hardcoded string).
RSpec.describe Ai::ContentRegistry do
  after { described_class.reload! }

  it "loads and freezes the shipped ontology" do
    expect(described_class.data).to be_frozen
    expect(described_class.data["schema_version"]).to eq(1)
  end

  it "declares every block type the renderer maps (and nothing it can't render)" do
    expect(described_class.block_types)
      .to match_array(%w[text kv_table table media sparkline chart score ttb suggestion])
  end

  it "declares the chart vizzes including heart" do
    expect(described_class.chart_vizzes).to match_array(%w[area bar heatmap heart])
  end

  it "limits the palette to default, cyan, red, green" do
    expect(described_class.allowed_colors).to match_array(%w[default cyan red green])
  end

  it "answers limits by path with fallbacks" do
    expect(described_class.limit("max_blocks", default: 99)).to eq(12)
    expect(described_class.limit("text", "max_chars", default: 99)).to eq(4_000)
    expect(described_class.limit("text", "nope", default: 7)).to eq(7)
  end

  it "generates the pito_respond document from the ontology — every type, the rules, the styling" do
    doc = described_class.respond_description
    described_class.block_types.each { |t| expect(doc).to include(t) }
    expect(doc).to include("kaomoji")
    expect(doc).to include("NEVER use emoji")
    expect(doc).to include("**bold**")
    expect(doc).to include("cyan, red, green")
    expect(doc).to include("viz=heart")
    # THE STYLE LINE: presentation never leaks to the model.
    expect(doc.downcase).not_to include("gradient", "shimmer")
  end

  describe "validation" do
    def with_doc(doc)
      allow(YAML).to receive(:safe_load_file).and_return(doc)
      described_class.reload!
      described_class.data
    end

    let(:minimal) do
      {
        "schema_version" => 1,
        "rules"  => { "emoji" => "never" },
        "inline" => { "bold" => "**b**", "italic" => "*i*",
                      "colors" => { "allowed" => %w[default cyan], "notation" => "[cyan]x[/cyan]" } },
        "blocks" => { "text" => { "label" => "paragraph", "about" => "prose",
                                  "when_to_use" => "openers", "data" => { "text" => "String" } } },
        "limits" => { "max_blocks" => 12 }
      }
    end

    it "accepts a minimal valid document" do
      expect(with_doc(minimal)["blocks"].keys).to eq([ "text" ])
    end

    it "rejects unknown top-level keys with a did-you-mean" do
      expect { with_doc(minimal.merge("blockz" => {})) }
        .to raise_error(described_class::InvalidContent, /blockz.*did you mean.*blocks/m)
    end

    it "rejects unknown block keys" do
      doc = minimal.deep_dup
      doc["blocks"]["text"]["abuot"] = "typo"
      expect { with_doc(doc) }.to raise_error(described_class::InvalidContent, /abuot/)
    end

    it "rejects a block missing its explanatory fields" do
      doc = minimal.deep_dup
      doc["blocks"]["text"].delete("when_to_use")
      expect { with_doc(doc) }.to raise_error(described_class::InvalidContent, /when_to_use/)
    end

    it "rejects vizzes outside the chart block" do
      doc = minimal.deep_dup
      doc["blocks"]["text"]["vizzes"] = {}
      expect { with_doc(doc) }.to raise_error(described_class::InvalidContent, /vizzes/)
    end

    it "rejects colors the renderer has no support code for" do
      doc = minimal.deep_dup
      doc["inline"]["colors"]["allowed"] = %w[default purple]
      expect { with_doc(doc) }.to raise_error(described_class::InvalidContent, /purple.*support code/m)
    end
  end
end
