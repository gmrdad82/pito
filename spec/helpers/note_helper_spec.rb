require "rails_helper"

RSpec.describe NoteHelper, type: :helper do
  # Markdown-aware word counting. Renders the body to HTML via
  # Commonmarker (matching the SSR `render_markdown` path), strips
  # tags to plain text, then tokenizes with `\p{Word}+`. The model's
  # `before_save :recompute_counts` calls this helper through
  # `body_for_counts`; the live editor counter mirrors the same shape
  # client-side so SSR and live rendering agree.
  describe ".word_count" do
    it "returns 0 for nil" do
      expect(described_class.word_count(nil)).to eq(0)
    end

    it "returns 0 for an empty string" do
      expect(described_class.word_count("")).to eq(0)
    end

    it "returns 0 for whitespace-only input" do
      expect(described_class.word_count("   \n\t")).to eq(0)
    end

    it "counts plain prose word by word" do
      expect(described_class.word_count("Hello world")).to eq(2)
    end

    it "strips ATX headings — `# Hi\\nHow are you all doing?` reports 6 words" do
      # The defining example: `#` is consumed by the markdown render
      # and never reaches the tokenizer; only `Hi How are you all doing`
      # survives strip_tags.
      body = "# Hi\nHow are you all doing?"
      expect(described_class.word_count(body)).to eq(6)
    end

    it "treats list items as their content (3 items, 1 word each)" do
      expect(described_class.word_count("- one\n- two\n- three")).to eq(3)
    end

    it "counts code-fence content as plain text" do
      # Fence: ```\nfoo\n``` — `foo` survives the strip; fence
      # delimiters never reach the tokenizer.
      body = "```\nfoo\n```"
      expect(described_class.word_count(body)).to eq(1)
    end

    it "does not count emphasis / link markdown punctuation as words" do
      body = "**bold** and *italic* and [link](https://example.com)"
      # Commonmarker renders the link's visible text only; the href is
      # an attribute and is dropped by strip_tags. Tokens: bold, and,
      # italic, and, link → 5.
      expect(described_class.word_count(body)).to eq(5)
    end

    it "counts unicode letters (`héllo` is one word)" do
      expect(described_class.word_count("héllo")).to eq(1)
    end

    it "uses module_function so the API is `NoteHelper.word_count(...)`" do
      # Sanity check that the singleton-style call site works without
      # `include`-ing the module — mirrors how the model invokes it.
      expect { described_class.word_count("test") }.not_to raise_error
    end
  end

  # Compact word-count label rendered in the projects index notes
  # column. Wraps `number_with_delimiter` with a trailing `w` suffix
  # so `6` reads `"6w"` and `12_232` reads `"12,232w"`. nil / 0 fall
  # back to the em-dash placeholder used elsewhere in numeric table
  # cells (`FootageHelper::EMPTY_VALUE` shares the glyph).
  describe ".human_words" do
    it "returns the em-dash placeholder for nil" do
      expect(described_class.human_words(nil)).to eq("—")
    end

    it "returns the em-dash placeholder for zero" do
      expect(described_class.human_words(0)).to eq("—")
    end

    it "renders 1 as `1w`" do
      expect(described_class.human_words(1)).to eq("1w")
    end

    it "renders 6 as `6w`" do
      expect(described_class.human_words(6)).to eq("6w")
    end

    it "renders 12 as `12w`" do
      expect(described_class.human_words(12)).to eq("12w")
    end

    it "renders 1234 as `1,234w` (comma thousands separator)" do
      expect(described_class.human_words(1234)).to eq("1,234w")
    end

    it "renders 12_232 as `12,232w`" do
      expect(described_class.human_words(12_232)).to eq("12,232w")
    end

    it "renders 1_000_000 as `1,000,000w`" do
      expect(described_class.human_words(1_000_000)).to eq("1,000,000w")
    end

    it "is callable as `NoteHelper.human_words(...)` (module_function API)" do
      expect { described_class.human_words(42) }.not_to raise_error
    end
  end
end
