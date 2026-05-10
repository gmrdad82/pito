require "rails_helper"

# Phase 8 — tenant drop. The previous `.tenant_root(tenant)` helper is
# gone; consumers reach assets via domain-specific top-level segments
# (`composites/`, `thumbnails/`, `exports/`, `footage_thumbs/`).
RSpec.describe Pito::AssetsRoot do
  let(:tmp_root) { Dir.mktmpdir("pito-assets-spec") }

  around do |example|
    prev = ENV["PITO_ASSETS_PATH"]
    ENV["PITO_ASSETS_PATH"] = tmp_root
    example.run
  ensure
    ENV["PITO_ASSETS_PATH"] = prev
    FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
  end

  describe ".root" do
    it "returns the env-var path as an absolute Pathname" do
      expect(described_class.root).to eq(Pathname.new(tmp_root).cleanpath)
      expect(described_class.root).to be_absolute
    end

    it "falls back to /var/lib/pito-assets when PITO_ASSETS_PATH is unset" do
      ENV.delete("PITO_ASSETS_PATH")
      expect(described_class.root.to_s).to eq("/var/lib/pito-assets")
    end

    it "anchors a relative env value to Rails.root" do
      ENV["PITO_ASSETS_PATH"] = "tmp/pito-assets-relative"
      expect(described_class.root).to eq(Rails.root.join("tmp/pito-assets-relative").cleanpath)
      expect(described_class.root).to be_absolute
    end
  end

  describe ".path with the new domain-specific segments" do
    it "resolves composites under <root>/composites/<file>" do
      expect(described_class.path("composites", "cover.png"))
        .to eq(Pathname.new(tmp_root).join("composites/cover.png"))
    end

    it "resolves thumbnails under <root>/thumbnails/<id>/<frame>" do
      expect(described_class.path("thumbnails", "1", "frame.jpg"))
        .to eq(Pathname.new(tmp_root).join("thumbnails/1/frame.jpg"))
    end

    it "resolves exports under <root>/exports/<file>" do
      expect(described_class.path("exports", "out.mp4"))
        .to eq(Pathname.new(tmp_root).join("exports/out.mp4"))
    end

    it "resolves footage thumbs under <root>/footage_thumbs/<id>/<tier>/<frame>" do
      expect(described_class.path("footage_thumbs", "1", "m", "00-01-02.jpg"))
        .to eq(Pathname.new(tmp_root).join("footage_thumbs/1/m/00-01-02.jpg"))
    end

    it "rejects empty segment list" do
      expect { described_class.path }.to raise_error(Pito::AssetsRoot::Error, /required/)
    end

    it "rejects empty string segment" do
      expect { described_class.path("") }.to raise_error(Pito::AssetsRoot::Error, /empty/)
    end

    it "rejects whitespace-only segment" do
      expect { described_class.path("   ") }.to raise_error(Pito::AssetsRoot::Error, /empty/)
    end

    it "rejects an absolute-path segment" do
      expect { described_class.path("/etc", "passwd") }
        .to raise_error(Pito::AssetsRoot::Error, /relative/)
    end

    it "rejects traversal that escapes the root" do
      expect { described_class.path("..", "etc") }
        .to raise_error(Pito::AssetsRoot::Error, /escapes/)
    end

    it "rejects nested traversal that escapes the root" do
      expect { described_class.path("a", "..", "..", "etc") }
        .to raise_error(Pito::AssetsRoot::Error, /escapes/)
    end

    it "permits internal traversal that stays within the root" do
      result = described_class.path("a", "b", "..", "c")
      expect(result).to eq(Pathname.new(tmp_root).join("a/c"))
    end
  end

  describe ".ensure_dir!" do
    it "creates the directory and returns the Pathname" do
      target = described_class.ensure_dir!("footage_thumbs", "1")
      expect(target).to be_directory
      expect(target).to eq(Pathname.new(tmp_root).join("footage_thumbs/1"))
    end

    it "is idempotent on existing directories" do
      described_class.ensure_dir!("repeat")
      expect { described_class.ensure_dir!("repeat") }.not_to raise_error
      expect(Pathname.new(tmp_root).join("repeat")).to be_directory
    end

    it "preserves files inside an existing directory" do
      first = described_class.ensure_dir!("preserve")
      File.write(first.join("keepme.txt"), "hi")

      described_class.ensure_dir!("preserve")

      expect(File.read(first.join("keepme.txt"))).to eq("hi")
    end

    it "rejects traversal" do
      expect { described_class.ensure_dir!("..", "outside") }
        .to raise_error(Pito::AssetsRoot::Error, /escapes/)
    end
  end

  describe "Phase 8 — tenant_root removed" do
    it "no longer responds to tenant_root" do
      expect(described_class).not_to respond_to(:tenant_root)
    end
  end

  describe ".inside?" do
    let(:base) { Pathname.new(tmp_root).cleanpath }

    it "is true for the base itself" do
      expect(described_class.inside?(base, base)).to be true
    end

    it "is true for a descendant" do
      expect(described_class.inside?(base.join("a"), base)).to be true
    end

    it "is true for a deep descendant" do
      expect(described_class.inside?(base.join("a/b/c.jpg"), base)).to be true
    end

    it "is false for a sibling sharing a prefix" do
      sibling = Pathname.new("#{tmp_root}-sibling").cleanpath
      expect(described_class.inside?(sibling, base)).to be false
    end

    it "is false for an unrelated absolute path" do
      expect(described_class.inside?(Pathname.new("/etc/passwd"), base)).to be false
    end
  end
end
