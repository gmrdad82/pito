require "rails_helper"

# Phase 27 §01h — Compositable shared interface.
#
# Tested via both host models (Bundle and Collection) to confirm the
# mixin behaves identically regardless of which row owns the columns.
RSpec.describe Compositable do
  describe "Bundle host" do
    let(:bundle) { create(:bundle, bundle_type: :custom) }

    it "is included in Bundle" do
      expect(Bundle.ancestors).to include(Compositable)
    end

    describe "#composite_cover_url" do
      it "returns nil when composite_cover_path is blank" do
        expect(bundle.composite_cover_url).to be_nil
      end

      it "returns /composites/<basename> when present" do
        bundle.update_columns(composite_cover_path: "composites/custom-#{bundle.id}.jpg")
        expect(bundle.composite_cover_url).to eq("/composites/custom-#{bundle.id}.jpg")
      end
    end

    describe "#composite_cover_absolute_path" do
      it "returns nil when path is blank" do
        expect(bundle.composite_cover_absolute_path).to be_nil
      end

      it "returns the absolute Pathname under the assets root" do
        bundle.update_columns(composite_cover_path: "composites/custom-#{bundle.id}.jpg")
        expect(bundle.composite_cover_absolute_path)
          .to eq(Pito::AssetsRoot.path("composites", "custom-#{bundle.id}.jpg"))
      end

      it "returns nil when the stored path escapes the assets root" do
        bundle.update_columns(composite_cover_path: "../../etc/passwd")
        expect(bundle.composite_cover_absolute_path).to be_nil
      end
    end

    describe "#sweep_composite_cover_file" do
      let(:fixture) { Rails.root.join("spec/fixtures/files/cover_tile.jpg") }

      it "deletes the on-disk file when present" do
        target = Pito::AssetsRoot.path("composites", "custom-#{bundle.id}.jpg")
        FileUtils.mkdir_p(target.dirname)
        FileUtils.cp(fixture, target)
        bundle.update_columns(composite_cover_path: "composites/custom-#{bundle.id}.jpg")

        bundle.sweep_composite_cover_file
        expect(File.exist?(target)).to be(false)
      end

      it "swallows Errno::ENOENT when the file is already gone" do
        bundle.update_columns(composite_cover_path: "composites/missing-9999.jpg")
        expect { bundle.sweep_composite_cover_file }.not_to raise_error
      end

      it "swallows generic StandardError so destroy never fails on cache state" do
        bundle.update_columns(composite_cover_path: "composites/custom-#{bundle.id}.jpg")
        target = Pito::AssetsRoot.path("composites", "custom-#{bundle.id}.jpg")
        FileUtils.mkdir_p(target.dirname)
        FileUtils.cp(fixture, target)

        allow(File).to receive(:delete).and_raise(StandardError, "synthetic")
        expect { bundle.sweep_composite_cover_file }.not_to raise_error
      end
    end
  end

  describe "Collection host" do
    let(:collection) { create(:collection) }

    it "is included in Collection" do
      expect(Collection.ancestors).to include(Compositable)
    end

    it "renders #composite_cover_url with the collection-<id> filename" do
      collection.update_columns(composite_cover_path: "composites/collection-#{collection.id}.jpg")
      expect(collection.composite_cover_url).to eq("/composites/collection-#{collection.id}.jpg")
    end

    it "is independent of #cover_url (which carries the ?v= fingerprint)" do
      collection.update_columns(
        composite_cover_path:     "composites/collection-#{collection.id}.jpg",
        composite_cover_checksum: "abc"
      )
      expect(collection.composite_cover_url).to eq("/composites/collection-#{collection.id}.jpg")
      expect(collection.cover_url).to eq("/composites/collection-#{collection.id}.jpg?v=abc")
    end
  end
end
