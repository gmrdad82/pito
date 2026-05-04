require "rails_helper"

RSpec.describe NoteTitleParser do
  describe ".parse" do
    it "returns the fallback for nil body" do
      expect(described_class.parse(nil)).to eq("Untitled note")
    end

    it "returns the fallback for an empty body" do
      expect(described_class.parse("")).to eq("Untitled note")
    end

    it "extracts the title from a leading ATX H1" do
      expect(described_class.parse("# Hello world\n\nBody.")).to eq("Hello world")
    end

    it "skips leading blank lines before the H1" do
      expect(described_class.parse("\n\n# Heading\n\nBody.")).to eq("Heading")
    end

    it "ignores higher heading levels" do
      expect(described_class.parse("## Sub heading\n\nBody.")).to eq("Untitled note")
    end

    it "ignores Setext underline headings" do
      expect(described_class.parse("Hello world\n=========\n\nBody.")).to eq("Untitled note")
    end

    it "ignores YAML frontmatter" do
      body = "---\ntitle: Frontmatter title\n---\n\n# Real heading\n"
      expect(described_class.parse(body)).to eq("Untitled note")
    end

    it "ignores HTML <h1> tags" do
      expect(described_class.parse("<h1>Hello</h1>\n")).to eq("Untitled note")
    end

    it "truncates titles to TITLE_MAX_LENGTH characters" do
      long = "x" * 100
      title = described_class.parse("# #{long}")
      expect(title.length).to eq(Note::TITLE_MAX_LENGTH)
    end

    it "returns the fallback for a heading-only line with no text" do
      expect(described_class.parse("# \n\nBody.")).to eq("Untitled note")
    end
  end
end
