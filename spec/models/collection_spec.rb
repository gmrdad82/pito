require "rails_helper"

# Phase 8 — tenant drop. Collection is install-wide.
RSpec.describe Collection, type: :model do
  subject { build(:collection) }

  describe "associations" do
    it "does not declare a tenant association" do
      expect(Collection.reflect_on_association(:tenant)).to be_nil
    end
    it { is_expected.to have_many(:games).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
  end

  describe "default name" do
    it 'defaults to "Untitled collection"' do
      collection = Collection.create!
      expect(collection.name).to eq("Untitled collection")
    end
  end

  # Phase 27 §01h — composite cover support.
  describe "#cover_url" do
    it "returns nil when composite_cover_checksum is blank" do
      collection = create(:collection)
      expect(collection.cover_url).to be_nil
    end

    it "returns the composite URL with ?v=<checksum> when present" do
      collection = create(:collection)
      collection.update_columns(composite_cover_checksum: "abc123def456")
      expect(collection.cover_url).to eq("/composites/collection-#{collection.id}.jpg?v=abc123def456")
    end

    it "ignores the variant: kwarg (reserved for future shelf-size variants)" do
      collection = create(:collection)
      collection.update_columns(composite_cover_checksum: "abc")
      expect(collection.cover_url(variant: :anything)).to eq("/composites/collection-#{collection.id}.jpg?v=abc")
    end

    it "ignores variant: nil (default)" do
      collection = create(:collection)
      collection.update_columns(composite_cover_checksum: "abc")
      expect(collection.cover_url(variant: nil)).to eq(collection.cover_url)
    end
  end

  describe "Compositable mixin" do
    it "includes the Compositable concern" do
      expect(Collection.ancestors).to include(Compositable)
    end

    it "exposes composite_cover_url via the concern" do
      collection = create(:collection)
      collection.update_columns(composite_cover_path: "composites/collection-#{collection.id}.jpg")
      expect(collection.composite_cover_url).to eq("/composites/collection-#{collection.id}.jpg")
    end

    it "exposes composite_cover_absolute_path via the concern" do
      collection = create(:collection)
      collection.update_columns(composite_cover_path: "composites/collection-#{collection.id}.jpg")
      expect(collection.composite_cover_absolute_path)
        .to eq(Pito::AssetsRoot.path("composites", "collection-#{collection.id}.jpg"))
    end

    it "composite_cover_url is nil when path is blank" do
      collection = create(:collection)
      expect(collection.composite_cover_url).to be_nil
    end
  end

  describe "before_destroy :sweep_composite_cover_file" do
    let(:collection) { create(:collection) }
    let(:fixture)    { Rails.root.join("spec/fixtures/files/cover_tile.jpg") }

    before do
      target = Pito::AssetsRoot.path("composites", "collection-#{collection.id}.jpg")
      FileUtils.mkdir_p(target.dirname)
      FileUtils.cp(fixture, target)
      collection.update_columns(
        composite_cover_path: "composites/collection-#{collection.id}.jpg"
      )
    end

    after do
      target = Pito::AssetsRoot.path("composites", "collection-#{collection.id}.jpg")
      File.delete(target) if File.exist?(target)
    rescue Pito::AssetsRoot::Error
      nil
    end

    it "removes the on-disk composite file when destroyed" do
      target = Pito::AssetsRoot.path("composites", "collection-#{collection.id}.jpg")
      expect(File.exist?(target)).to be(true)

      collection.destroy!
      expect(File.exist?(target)).to be(false)
    end

    it "survives Errno::ENOENT (file already gone) without raising" do
      target = Pito::AssetsRoot.path("composites", "collection-#{collection.id}.jpg")
      File.delete(target)
      expect { collection.destroy! }.not_to raise_error
    end

    it "no-ops when composite_cover_path is blank (no destroy crash)" do
      collection.update_columns(composite_cover_path: nil)
      expect { collection.destroy! }.not_to raise_error
    end
  end
end
