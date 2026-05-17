require "rails_helper"
require "rake"
require "tmpdir"
require "fileutils"

# Coverage push (2026-05-17). Operator-facing rake task that reaps
# orphan composite cover files from
# `<PITO_ASSETS_PATH>/covers/bundles/`. Walks the per-bundle subdir
# tree (`covers/bundles/<id>/composite.jpg`), deletes every composite
# whose parent dir id does NOT match a current Bundle's
# `composite_cover_path`, and prints the count. Idempotent; tolerant
# of an already-deleted file (Errno::ENOENT swallowed mid-walk).
#
# The on-disk layout is `covers/bundles/<bundle_id>/composite.jpg`
# (unified under the single `/covers/` namespace 2026-05-17; legacy
# `composites/bundle-<id>.jpg` retired). `composite_cover_path` is the
# relative path from the assets root (e.g.
# `covers/bundles/12/composite.jpg`). The specs scope
# `PITO_ASSETS_PATH` to a per-example tmpdir so the working directory
# is real (no FakeFS or stubs) and the assertions are purely
# file-system state checks.
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

  let(:bundles_dir) { Pito::AssetsRoot.path("covers", "bundles") }

  def write_composite(bundle_id, body: "JPEG")
    dir = bundles_dir.join(bundle_id.to_s)
    FileUtils.mkdir_p(dir)
    path = dir.join("composite.jpg")
    File.binwrite(path, body)
    path
  end

  def relative_path_for(bundle_id)
    "covers/bundles/#{bundle_id}/composite.jpg"
  end

  describe "pito:bundles:reap_orphans" do
    it "deletes a composite whose bundle id is not referenced by any Bundle" do
      orphan = write_composite(999999)
      task.invoke
      expect(File.exist?(orphan)).to be(false)
    end

    it "keeps composites whose path matches a Bundle#composite_cover_path" do
      bundle = create(:bundle)
      kept = write_composite(bundle.id)
      bundle.update_columns(composite_cover_path: relative_path_for(bundle.id))

      task.invoke

      expect(File.exist?(kept)).to be(true)
    end

    it "prints `reaped 0 orphan composite covers.` when the directory has no orphans" do
      bundle = create(:bundle)
      write_composite(bundle.id)
      bundle.update_columns(composite_cover_path: relative_path_for(bundle.id))

      expect { task.invoke }.to output(/reaped 0 orphan composite covers\./).to_stdout
    end

    it "prints `reaped 1 orphan composite cover.` (singular form) when exactly one orphan is removed" do
      write_composite(1)
      expect { task.invoke }.to output(/reaped 1 orphan composite cover\./).to_stdout
    end

    it "prints the pluralised summary when more than one orphan is removed" do
      write_composite(1)
      write_composite(2)
      expect { task.invoke }.to output(/reaped 2 orphan composite covers\./).to_stdout
    end

    it "no-ops gracefully when the bundles directory does not exist" do
      expect(Dir.exist?(bundles_dir)).to be(false)
      expect { task.invoke }.not_to raise_error
    end

    it "is idempotent — re-running after a sweep reports zero" do
      write_composite(1)
      task.invoke
      task.reenable
      expect { task.invoke }.to output(/reaped 0 orphan composite covers\./).to_stdout
    end

    it "tolerates a file that disappears mid-walk (Errno::ENOENT)" do
      orphan = write_composite(1)
      allow(File).to receive(:delete).with(orphan.to_s).and_raise(Errno::ENOENT)
      expect { task.invoke }.not_to raise_error
    end

    it "keeps multiple matching files when several Bundles each have composite_cover_path set" do
      a = create(:bundle)
      b = create(:bundle)

      orphan_id = [ a.id, b.id ].max + 100

      write_composite(a.id)
      write_composite(b.id)
      write_composite(orphan_id)

      a.update_columns(composite_cover_path: relative_path_for(a.id))
      b.update_columns(composite_cover_path: relative_path_for(b.id))

      task.invoke

      expect(File.exist?(bundles_dir.join(a.id.to_s, "composite.jpg"))).to be(true)
      expect(File.exist?(bundles_dir.join(b.id.to_s, "composite.jpg"))).to be(true)
      expect(File.exist?(bundles_dir.join(orphan_id.to_s, "composite.jpg"))).to be(false)
    end
  end
end
