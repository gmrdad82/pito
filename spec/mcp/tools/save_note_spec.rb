require "rails_helper"
require_relative "../../../app/mcp/tools/save_note"

RSpec.describe Mcp::Tools::SaveNote do
  let(:tmproot) { Pathname.new(Dir.mktmpdir("pito-save-note-spec")) }

  before do
    @real_root = Rails.root
    Rails.application.config.root = tmproot
    allow(Rails).to receive(:root).and_return(tmproot)
  end

  after do
    Rails.application.config.root = @real_root
    allow(Rails).to receive(:root).and_call_original
    FileUtils.remove_entry(tmproot) if tmproot.exist?
  end

  describe "filename format" do
    it "creates docs/notes/<timestamp>-<slug>.md with exact bytes" do
      result = described_class.call(content: "# Hello\nworld", slug: "hello-world")
      data = JSON.parse(result.content.first[:text])

      expect(data["path"]).to match(%r{\Adocs/notes/\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}-hello-world\.md\z})
      expect(File.read(tmproot.join(data["path"]))).to eq("# Hello\nworld")
      expect(data["saved_at"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it "creates the docs/notes/ folder on first use" do
      expect(tmproot.join("docs/notes")).not_to exist

      described_class.call(content: "x", slug: "first")

      expect(tmproot.join("docs/notes")).to be_directory
    end

    it "falls back to slug 'note' when no slug is provided" do
      result = described_class.call(content: "anything")
      data = JSON.parse(result.content.first[:text])

      expect(data["path"]).to match(%r{-note\.md\z})
    end
  end

  describe "slug sanitization" do
    it "lowercases and replaces spaces with hyphens" do
      result = described_class.call(content: "x", slug: "My Note!")
      data = JSON.parse(result.content.first[:text])

      expect(data["path"]).to match(%r{-my-note\.md\z})
    end

    it "drops every character outside [a-z0-9-]" do
      result = described_class.call(content: "x", slug: "Foo@Bar#123")
      data = JSON.parse(result.content.first[:text])

      expect(data["path"]).to match(%r{-foobar123\.md\z})
    end

    it "collapses runs of hyphens" do
      result = described_class.call(content: "x", slug: "a---b")
      data = JSON.parse(result.content.first[:text])

      expect(data["path"]).to match(%r{-a-b\.md\z})
    end

    it "strips leading and trailing hyphens" do
      result = described_class.call(content: "x", slug: "-trim-me-")
      data = JSON.parse(result.content.first[:text])

      expect(data["path"]).to match(%r{-trim-me\.md\z})
    end

    it "caps the slug at 50 characters" do
      long = "a" * 200
      result = described_class.call(content: "x", slug: long)
      data = JSON.parse(result.content.first[:text])

      filename = File.basename(data["path"], ".md")
      slug_part = filename.sub(/\A\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}-/, "")
      expect(slug_part.length).to eq(50)
    end

    it "falls back to 'note' when sanitization yields empty" do
      result = described_class.call(content: "x", slug: "!!!")
      data = JSON.parse(result.content.first[:text])

      expect(data["path"]).to match(%r{-note\.md\z})
    end

    it "falls back to 'note' for an empty slug string" do
      result = described_class.call(content: "x", slug: "")
      data = JSON.parse(result.content.first[:text])

      expect(data["path"]).to match(%r{-note\.md\z})
    end
  end

  describe "collisions" do
    it "appends -2/-3 when sub-second timestamps collide" do
      frozen = Time.utc(2026, 5, 4, 12, 30, 45)
      allow(Time).to receive(:now).and_return(frozen)

      first = described_class.call(content: "first", slug: "hello")
      second = described_class.call(content: "second", slug: "hello")
      third = described_class.call(content: "third", slug: "hello")

      first_path = JSON.parse(first.content.first[:text])["path"]
      second_path = JSON.parse(second.content.first[:text])["path"]
      third_path = JSON.parse(third.content.first[:text])["path"]

      expect(first_path).to match(%r{2026-05-04-12-30-45-hello\.md\z})
      expect(second_path).to match(%r{2026-05-04-12-30-45-hello-2\.md\z})
      expect(third_path).to match(%r{2026-05-04-12-30-45-hello-3\.md\z})

      # All three files exist with the right content.
      expect(File.read(tmproot.join(first_path))).to eq("first")
      expect(File.read(tmproot.join(second_path))).to eq("second")
      expect(File.read(tmproot.join(third_path))).to eq("third")
    end
  end

  describe "validation" do
    it "rejects nil content" do
      result = described_class.call(content: nil)
      expect(result.to_h[:isError]).to be true
      expect(result.content.first[:text]).to match(/content/)
    end

    it "rejects empty content" do
      result = described_class.call(content: "")
      expect(result.to_h[:isError]).to be true
      expect(result.content.first[:text]).to match(/content/)
    end
  end

  describe ".sanitize_slug" do
    it "returns 'note' for nil" do
      expect(described_class.sanitize_slug(nil)).to eq("note")
    end

    it "returns 'note' for slug that sanitizes to empty" do
      expect(described_class.sanitize_slug("!!!")).to eq("note")
    end

    it "returns 'my-note' for 'My Note!'" do
      expect(described_class.sanitize_slug("My Note!")).to eq("my-note")
    end
  end
end
