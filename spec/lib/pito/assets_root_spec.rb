require "rails_helper"

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

  describe ".path" do
    it "joins one segment under the root" do
      expect(described_class.path("footage_thumbs")).to eq(Pathname.new(tmp_root).join("footage_thumbs"))
    end

    it "joins many segments under the root" do
      result = described_class.path("tenants", "1", "footage_thumbs", "abc.jpg")
      expect(result).to eq(Pathname.new(tmp_root).join("tenants/1/footage_thumbs/abc.jpg"))
    end

    it "returns an absolute Pathname" do
      expect(described_class.path("anything")).to be_absolute
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

  describe ".tenant_root" do
    let(:tenant_a) { instance_double("Tenant", id: 42) }
    let(:tenant_b) { instance_double("Tenant", id: 7) }

    it "returns <root>/<tenant_id>/ as a Pathname" do
      expect(described_class.tenant_root(tenant_a))
        .to eq(Pathname.new(tmp_root).join("42"))
    end

    it "creates the tenant directory on first call" do
      result = described_class.tenant_root(tenant_a)
      expect(result).to be_directory
    end

    it "is idempotent across repeat calls" do
      first = described_class.tenant_root(tenant_a)
      File.write(first.join("seed.txt"), "x")

      second = described_class.tenant_root(tenant_a)
      expect(second).to eq(first)
      expect(File.read(first.join("seed.txt"))).to eq("x")
    end

    it "isolates tenant A from tenant B" do
      a = described_class.tenant_root(tenant_a)
      b = described_class.tenant_root(tenant_b)

      expect(a).not_to eq(b)
      expect(a.to_s).not_to start_with(b.to_s + "/")
      expect(b.to_s).not_to start_with(a.to_s + "/")
    end

    it "raises when tenant is nil" do
      expect { described_class.tenant_root(nil) }
        .to raise_error(Pito::AssetsRoot::Error, /tenant/)
    end

    it "raises when tenant#id is nil" do
      tenant = instance_double("Tenant", id: nil)
      expect { described_class.tenant_root(tenant) }
        .to raise_error(Pito::AssetsRoot::Error, /id/)
    end

    it "works with a real persisted Tenant" do
      tenant = Tenant.create!(name: "AssetsRoot Spec", slug: "assets-root-spec-#{SecureRandom.hex(4)}")
      result = described_class.tenant_root(tenant)
      expect(result).to eq(Pathname.new(tmp_root).join(tenant.id.to_s))
      expect(result).to be_directory
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
