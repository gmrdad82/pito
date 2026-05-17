require "rails_helper"

# Phase 27 §01h / Phase 27 follow-up (2026-05-17) — Compositable
# shared interface. After the 2026-05-17 Collection→Bundle
# consolidation, Bundle is the only host (Collection model was
# removed). Composite path layout is now
# `covers/bundles/<id>/composite.jpg` (unified under the single
# `/covers/` namespace alongside `covers/games/<id>/master.jpg`).
RSpec.describe Compositable do
  describe "Bundle host" do
    let(:bundle) { create(:bundle) }

    it "is included in Bundle" do
      expect(Bundle.ancestors).to include(Compositable)
    end

    describe "#composite_cover_url" do
      it "returns nil when composite_cover_path is blank" do
        expect(bundle.composite_cover_url).to be_nil
      end

      it "returns /<composite_cover_path> when present" do
        bundle.update_columns(composite_cover_path: "covers/bundles/#{bundle.id}/composite.jpg")
        expect(bundle.composite_cover_url).to eq("/covers/bundles/#{bundle.id}/composite.jpg")
      end
    end

    describe "#composite_cover_absolute_path" do
      it "returns nil when path is blank" do
        expect(bundle.composite_cover_absolute_path).to be_nil
      end

      it "returns the absolute Pathname under the assets root" do
        bundle.update_columns(composite_cover_path: "covers/bundles/#{bundle.id}/composite.jpg")
        expect(bundle.composite_cover_absolute_path)
          .to eq(Pito::AssetsRoot.path("covers", "bundles", bundle.id.to_s, "composite.jpg"))
      end

      it "returns nil when the stored path escapes the assets root" do
        bundle.update_columns(composite_cover_path: "../../etc/passwd")
        expect(bundle.composite_cover_absolute_path).to be_nil
      end
    end

    describe "#sweep_composite_cover_file" do
      let(:fixture) { Rails.root.join("spec/fixtures/files/cover_tile.jpg") }

      it "deletes the on-disk file when present" do
        target = Pito::AssetsRoot.path("covers", "bundles", bundle.id.to_s, "composite.jpg")
        FileUtils.mkdir_p(target.dirname)
        FileUtils.cp(fixture, target)
        bundle.update_columns(composite_cover_path: "covers/bundles/#{bundle.id}/composite.jpg")

        bundle.sweep_composite_cover_file
        expect(File.exist?(target)).to be(false)
      end

      it "swallows Errno::ENOENT when the file is already gone" do
        bundle.update_columns(composite_cover_path: "covers/bundles/9999/composite.jpg")
        expect { bundle.sweep_composite_cover_file }.not_to raise_error
      end

      it "swallows generic StandardError so destroy never fails on cache state" do
        bundle.update_columns(composite_cover_path: "covers/bundles/#{bundle.id}/composite.jpg")
        target = Pito::AssetsRoot.path("covers", "bundles", bundle.id.to_s, "composite.jpg")
        FileUtils.mkdir_p(target.dirname)
        FileUtils.cp(fixture, target)

        allow(File).to receive(:delete).and_raise(StandardError, "synthetic")
        expect { bundle.sweep_composite_cover_file }.not_to raise_error
      end
    end
  end
end
