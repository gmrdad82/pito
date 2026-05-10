require "rails_helper"

# Phase 20 — friendly URLs. Footage uses the `local_path` basename
# (sans extension), parameterized via Pito::SlugBuilder. On collision
# (two footages with the same basename), the slug appends `-<id>` to
# disambiguate.
RSpec.describe Footage, type: :model do
  describe "#url_slug" do
    it "is the parameterized basename of local_path (no extension)" do
      footage = create(:footage, local_path: "/tmp/footage/My Cool Clip.mp4",
                                 filename: "My Cool Clip.mp4")
      expect(footage.url_slug).to eq("my-cool-clip")
    end

    it "appends -<id> on basename collision" do
      a = create(:footage, local_path: "/dir-one/clip.mp4", filename: "clip.mp4")
      b = create(:footage, local_path: "/dir-two/clip.mp4", filename: "clip.mp4")
      expect(a.url_slug).to eq("clip-#{a.id}").or eq("clip")
      expect(b.url_slug).to eq("clip-#{b.id}").or eq("clip")
      expect(a.url_slug).not_to eq(b.url_slug)
    end

    it "strips path / extension cleanly" do
      footage = create(:footage, local_path: "/very/deep/path/to/footage_1080p.mov",
                                 filename: "footage_1080p.mov")
      expect(footage.url_slug).to eq("footage-1080p")
    end

    it "falls back to footage-<id> when local_path collapses to nothing" do
      footage = create(:footage, local_path: "/tmp/@@@.mp4", filename: "@@@.mp4")
      expect(footage.url_slug).to eq("footage-#{footage.id}")
    end
  end

  describe "#to_param" do
    it "returns url_slug" do
      footage = create(:footage, local_path: "/x/sample.mov", filename: "sample.mov")
      expect(footage.to_param).to eq(footage.url_slug)
    end
  end

  describe "Footage.friendly.find" do
    it "resolves by basename slug" do
      footage = create(:footage, local_path: "/x/example.mov", filename: "example.mov")
      expect(Footage.friendly.find("example")).to eq(footage)
    end

    it "resolves by basename-<id> slug after collision" do
      a = create(:footage, local_path: "/p/a/clip.mp4", filename: "clip.mp4")
      b = create(:footage, local_path: "/p/b/clip.mp4", filename: "clip.mp4")
      expect(Footage.friendly.find(a.url_slug)).to eq(a)
      expect(Footage.friendly.find(b.url_slug)).to eq(b)
    end

    it "resolves by integer id (backwards compat)" do
      footage = create(:footage, local_path: "/y/test.mp4", filename: "test.mp4")
      expect(Footage.friendly.find(footage.id)).to eq(footage)
    end

    it "resolves by stringified integer id" do
      footage = create(:footage, local_path: "/y/test2.mp4", filename: "test2.mp4")
      expect(Footage.friendly.find(footage.id.to_s)).to eq(footage)
    end

    it "raises RecordNotFound on a miss" do
      expect { Footage.friendly.find("does-not-exist") }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
