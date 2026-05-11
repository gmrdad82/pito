require "rails_helper"

RSpec.describe DiffHelper, type: :helper do
  describe "#human_diff_value" do
    it "formats nil as a muted (empty) placeholder" do
      out = helper.human_diff_value("title", nil)
      expect(out).to include("(empty)")
      expect(out).to include("text-muted")
    end

    it "formats short text plainly" do
      out = helper.human_diff_value("title", "hello")
      expect(out).to include("hello")
    end

    it "truncates long descriptions to 240 chars with an ellipsis" do
      long = "a" * 300
      out = helper.human_diff_value("description", long)
      expect(out).to include("a" * 240 + "…")
    end

    it "renders tags as space-joined diff-tag spans" do
      out = helper.human_diff_value("tags", %w[gameplay walkthrough])
      expect(out).to include("gameplay")
      expect(out).to include("walkthrough")
      expect(out).to include("diff-tag")
    end

    it "renders an empty tags array as the (empty) placeholder" do
      out = helper.human_diff_value("tags", [])
      expect(out).to include("(empty)")
    end

    it "renders booleans as yes/no per the external-boundary rule" do
      expect(helper.human_diff_value("embeddable", true)).to include("yes")
      expect(helper.human_diff_value("embeddable", false)).to include("no")
    end

    it "renders integer counts with commas" do
      out = helper.human_diff_value("view_count", 1_234_567)
      expect(out).to include("1,234,567")
    end

    it "renders a coerced integer string" do
      out = helper.human_diff_value("view_count", "1000")
      expect(out).to include("1,000")
    end

    it "renders timestamps as ISO 8601" do
      out = helper.human_diff_value("published_at", "2026-01-01T00:00:00Z")
      expect(out).to include("2026-01-01T00:00:00Z")
    end

    it "renders thumbnail URLs with word-break inline style" do
      out = helper.human_diff_value("thumbnail_url", "https://i.ytimg.com/abc.jpg")
      expect(out).to include("https://i.ytimg.com/abc.jpg")
      expect(out).to include("word-break")
    end
  end

  describe "#diff_field_display_only?" do
    it "returns true for view_count, like_count, etc." do
      %w[view_count like_count comment_count duration_seconds thumbnail_url
         made_for_kids_effective published_at].each do |f|
        expect(helper.diff_field_display_only?(f)).to be(true), "expected `#{f}` display-only"
      end
    end

    it "returns false for title, description, tags, etc." do
      %w[title description tags category_id privacy_status publish_at
         embeddable public_stats_viewable self_declared_made_for_kids
         contains_synthetic_media].each do |f|
        expect(helper.diff_field_display_only?(f)).to be(false), "expected `#{f}` NOT display-only"
      end
    end
  end
end
