require "rails_helper"
require "rake"
require "tmpdir"
require "fileutils"

# Coverage push (2026-05-17). Operator-facing rake task that reaps
# orphan composite cover files from `<PITO_ASSETS_PATH>/composites/`.
# Walks the directory, deletes every `.jpg` whose basename does NOT
# match a current `Bundle#composite_cover_path` basename, and prints
# the count. Idempotent; tolerant of an already-deleted file
# (Errno::ENOENT swallowed mid-walk).
#
# The on-disk filename convention is `bundle-<bundle_id>.jpg` (after
# the 2026-05-17 Bundle simplification dropped the `bundle_type`
# discriminator from the prefix), anchored at
# `Pito::AssetsRoot.path("composites")`. The specs scope
# `PITO_ASSETS_PATH` to a per-example tmpdir so the working directory
# is real (no FakeFS or stubs) and the assertions are purely file-system
# state checks.
RSpec.describe "pito:bundles rake tasks" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/bundles",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task["pito:bundles:reap_orphans"] }

  let(:tmpdir) { Dir.mktmpdir("pito_bundles_spec") }

  around do |example|
    original = ENV["PITO_ASSETS_PATH"]
    ENV["PITO_ASSETS_PATH"] = tmpdir
    begin
      example.run
    ensure
      ENV["PITO_ASSETS_PATH"] = original
      FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir)
    end
  end

  before { task.reenable }

  let(:composites_dir) { Pito::AssetsRoot.path("composites") }

  def write_composite(basename, body: "JPEG")
    FileUtils.mkdir_p(composites_dir)
    path = composites_dir.join(basename)
    File.binwrite(path, body)
    path
  end

  describe "pito:bundles:reap_orphans" do
    it "deletes a `.jpg` whose basename is not referenced by any Bundle" do
      orphan = write_composite("bundle-999999.jpg")
      task.invoke
      expect(File.exist?(orphan)).to be(false)
    end

    it "keeps `.jpg` files whose basename matches a Bundle#composite_cover_path" do
      bundle = create(:bundle)
      kept_basename = "bundle-#{bundle.id}.jpg"
      kept = write_composite(kept_basename)
      bundle.update_columns(composite_cover_path: composites_dir.join(kept_basename).to_s)

      task.invoke

      expect(File.exist?(kept)).to be(true)
    end

    it "prints `reaped 0 orphan composite covers.` when the directory has no orphans" do
      bundle = create(:bundle)
      basename = "bundle-#{bundle.id}.jpg"
      write_composite(basename)
      bundle.update_columns(composite_cover_path: composites_dir.join(basename).to_s)

      expect { task.invoke }.to output(/reaped 0 orphan composite covers\./).to_stdout
    end

    it "prints `reaped 1 orphan composite cover.` (singular form) when exactly one orphan is removed" do
      write_composite("bundle-1.jpg")
      expect { task.invoke }.to output(/reaped 1 orphan composite cover\./).to_stdout
    end

    it "prints the pluralised summary when more than one orphan is removed" do
      write_composite("bundle-1.jpg")
      write_composite("bundle-2.jpg")
      expect { task.invoke }.to output(/reaped 2 orphan composite covers\./).to_stdout
    end

    it "no-ops gracefully when the composites directory does not exist" do
      expect(Dir.exist?(composites_dir)).to be(false)
      expect { task.invoke }.not_to raise_error
    end

    it "is idempotent — re-running after a sweep reports zero" do
      write_composite("bundle-1.jpg")
      task.invoke
      task.reenable
      expect { task.invoke }.to output(/reaped 0 orphan composite covers\./).to_stdout
    end

    it "tolerates a file that disappears mid-walk (Errno::ENOENT)" do
      orphan = write_composite("bundle-1.jpg")
      allow(File).to receive(:delete).with(orphan.to_s).and_raise(Errno::ENOENT)
      expect { task.invoke }.not_to raise_error
    end

    it "only inspects `.jpg` files (non-JPEG siblings are left alone)" do
      FileUtils.mkdir_p(composites_dir)
      stray = composites_dir.join("README.txt")
      File.binwrite(stray, "leave me alone")

      write_composite("bundle-7.jpg")
      task.invoke

      expect(File.exist?(stray)).to be(true)
    end

    it "keeps multiple matching files when several Bundles each have composite_cover_path set" do
      a = create(:bundle)
      b = create(:bundle)

      a_basename = "bundle-#{a.id}.jpg"
      b_basename = "bundle-#{b.id}.jpg"
      orphan_basename = "bundle-#{[ a.id, b.id ].max + 100}.jpg"

      write_composite(a_basename)
      write_composite(b_basename)
      write_composite(orphan_basename)

      a.update_columns(composite_cover_path: composites_dir.join(a_basename).to_s)
      b.update_columns(composite_cover_path: composites_dir.join(b_basename).to_s)

      task.invoke

      expect(File.exist?(composites_dir.join(a_basename))).to be(true)
      expect(File.exist?(composites_dir.join(b_basename))).to be(true)
      expect(File.exist?(composites_dir.join(orphan_basename))).to be(false)
    end
  end
end
