require "rails_helper"

RSpec.describe Bundle, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:bundle_members).dependent(:destroy) }
    it { is_expected.to have_many(:games).through(:bundle_members) }

    # Phase 14 §3 — video attribution links.
    it { is_expected.to have_many(:video_game_links).dependent(:destroy) }
    it { is_expected.to have_many(:videos).through(:video_game_links) }

    it "orders bundle_members by position" do
      bundle = create(:bundle, bundle_type: :custom)
      g1 = create(:game)
      g2 = create(:game)
      g3 = create(:game)
      bm1 = bundle.bundle_members.create!(game: g1)
      bm2 = bundle.bundle_members.create!(game: g2)
      bm3 = bundle.bundle_members.create!(game: g3)
      # Re-order via update_columns to bypass the position assignment guard.
      bm1.update_columns(position: 5)
      bm2.update_columns(position: 1)
      bm3.update_columns(position: 3)

      expect(bundle.reload.bundle_members.map(&:game_id))
        .to eq([ g2.id, g3.id, g1.id ])
    end
  end

  describe "enums" do
    it "exposes the four bundle_types" do
      expect(Bundle.bundle_types).to eq("series" => 0, "collection" => 1,
                                        "genre" => 2, "custom" => 3)
    end

    it "exposes the three igdb_source_types" do
      expect(Bundle.igdb_source_types).to eq("franchise" => 0,
                                             "source_collection" => 1,
                                             "source_genre" => 2)
    end

    it "supports type predicates" do
      bundle = build(:bundle, bundle_type: :series)
      expect(bundle.type_series?).to be(true)
      expect(bundle.type_custom?).to be(false)
    end

    it "supports igdb_source predicates" do
      bundle = build(:bundle, :series)
      expect(bundle.igdb_source_franchise?).to be(true)
      expect(bundle.igdb_source_source_collection?).to be(false)
    end
  end

  describe "validations" do
    it "requires name" do
      bundle = build(:bundle, name: nil)
      expect(bundle).not_to be_valid
      expect(bundle.errors[:name]).to be_present
    end

    it "limits name to 255" do
      bundle = build(:bundle, name: "a" * 256)
      expect(bundle).not_to be_valid
    end

    it "requires bundle_type" do
      bundle = Bundle.new(name: "x")
      bundle.bundle_type = nil
      bundle.valid?
      expect(bundle.errors[:bundle_type]).to be_present
    end

    context "igdb_source pair consistency" do
      it "custom bundle with both nil is valid" do
        expect(build(:bundle, bundle_type: :custom)).to be_valid
      end

      it "custom bundle with igdb_source_type set is invalid" do
        bundle = build(:bundle, bundle_type: :custom,
                                igdb_source_type: :franchise)
        expect(bundle).not_to be_valid
        expect(bundle.errors[:igdb_source_type]).to be_present
      end

      it "custom bundle with igdb_source_id set is invalid" do
        bundle = build(:bundle, bundle_type: :custom, igdb_source_id: 1)
        expect(bundle).not_to be_valid
        expect(bundle.errors[:igdb_source_id]).to be_present
      end

      it "non-custom bundle with both set is valid" do
        expect(build(:bundle, bundle_type: :series,
                              igdb_source_type: :franchise,
                              igdb_source_id: 1)).to be_valid
      end

      it "non-custom bundle with only one set is invalid" do
        bundle = build(:bundle, bundle_type: :series,
                                igdb_source_type: :franchise,
                                igdb_source_id: nil)
        expect(bundle).not_to be_valid
      end

      it "non-custom bundle with both nil is valid (allows starting empty)" do
        expect(build(:bundle, bundle_type: :series,
                              igdb_source_type: nil,
                              igdb_source_id: nil)).to be_valid
      end
    end

    context "igdb_source_id uniqueness scoped to igdb_source_type" do
      it "rejects two series bundles with the same franchise+id" do
        create(:bundle, bundle_type: :series,
                        igdb_source_type: :franchise, igdb_source_id: 1)
        dup = build(:bundle, bundle_type: :series,
                             igdb_source_type: :franchise, igdb_source_id: 1)
        expect(dup).not_to be_valid
      end

      it "allows two custom bundles with both nil" do
        create(:bundle, bundle_type: :custom)
        expect(build(:bundle, bundle_type: :custom)).to be_valid
      end

      it "allows series bundles with different igdb_source_ids" do
        create(:bundle, bundle_type: :series,
                        igdb_source_type: :franchise, igdb_source_id: 1)
        expect(build(:bundle, bundle_type: :series,
                              igdb_source_type: :franchise,
                              igdb_source_id: 2)).to be_valid
      end
    end

    it "raises ActiveRecord::RecordNotUnique on db-level duplicate" do
      create(:bundle, bundle_type: :series,
                      igdb_source_type: :franchise, igdb_source_id: 42)
      expect {
        Bundle.new(name: "dup", bundle_type: :series,
                   igdb_source_type: :franchise, igdb_source_id: 42)
              .save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "scopes" do
    it "filters by bundle_type" do
      s = create(:bundle, :series)
      _c = create(:bundle, bundle_type: :custom)
      expect(Bundle.where(bundle_type: :series)).to include(s)
      expect(Bundle.where(bundle_type: :series).count).to eq(1)
    end
  end

  describe "#composite_cover_url" do
    it "returns nil when path blank" do
      expect(build(:bundle, composite_cover_path: nil).composite_cover_url).to be_nil
    end

    it "returns the well-formed /composites/... URL when path present" do
      bundle = build(:bundle, composite_cover_path: "composites/custom-7.jpg")
      expect(bundle.composite_cover_url).to eq("/composites/custom-7.jpg")
    end
  end

  describe "#needs_cover_rebuild?" do
    let(:bundle) { create(:bundle, bundle_type: :custom) }

    it "is false on a fresh bundle with zero members and blank path/checksum" do
      expect(bundle.needs_cover_rebuild?).to be(false)
    end

    it "is true after a member with cover_image_id is added" do
      game = create(:game, :synced, cover_image_id: "abc123")
      bundle.bundle_members.create!(game: game)
      expect(bundle.reload.needs_cover_rebuild?).to be(true)
    end

    it "is false right after a successful build (checksum matches)" do
      game = create(:game, :synced, cover_image_id: "abc123")
      bundle.bundle_members.create!(game: game)
      layout = Composite::LayoutChooser.choose(1)
      checksum = Composite::Checksum.compute([ "abc123" ], layout.layout_name)
      bundle.update_columns(composite_cover_path: "composites/custom-#{bundle.id}.jpg",
                            composite_cover_checksum: checksum)
      expect(bundle.reload.needs_cover_rebuild?).to be(false)
    end

    it "is true after a member's cover_image_id changes" do
      game = create(:game, :synced, cover_image_id: "abc123")
      bundle.bundle_members.create!(game: game)
      layout = Composite::LayoutChooser.choose(1)
      checksum = Composite::Checksum.compute([ "abc123" ], layout.layout_name)
      bundle.update_columns(composite_cover_checksum: checksum)
      game.update!(cover_image_id: "xyz999")
      expect(bundle.reload.needs_cover_rebuild?).to be(true)
    end

    it "is true after a member is removed" do
      game1 = create(:game, :synced, cover_image_id: "a")
      game2 = create(:game, :synced, cover_image_id: "b")
      bundle.bundle_members.create!(game: game1)
      bundle.bundle_members.create!(game: game2)
      checksum = Composite::Checksum.compute(%w[a b], "pair")
      bundle.update_columns(composite_cover_checksum: checksum)
      bundle.bundle_members.find_by(game: game1).destroy!
      expect(bundle.reload.needs_cover_rebuild?).to be(true)
    end
  end

  describe "callbacks" do
    let(:bundle) { create(:bundle, bundle_type: :custom) }

    it "after_save enqueues BundleCoverBuild on create" do
      BundleCoverBuild.clear
      b = create(:bundle, bundle_type: :custom)
      # The create itself enqueues at least once via saved_change_to_id?
      expect(BundleCoverBuild.jobs.map { |j| j["args"].first }).to include(b.id)
    end

    it "does NOT enqueue on a name-only update (checksum unchanged)" do
      bundle # eager create
      BundleCoverBuild.clear
      bundle.update!(name: "new name")
      expect(BundleCoverBuild.jobs).to be_empty
    end
  end

  describe "#sweep_composite_cover_file (before_destroy)" do
    let(:bundle) { create(:bundle, bundle_type: :custom) }

    it "removes the on-disk composite cover file if present" do
      path = Pito::AssetsRoot.path("composites", "custom-#{bundle.id}.jpg")
      FileUtils.mkdir_p(path.dirname)
      File.write(path, "JPEG bytes")
      bundle.update_columns(composite_cover_path: "composites/custom-#{bundle.id}.jpg")

      expect { bundle.destroy! }.to change { File.exist?(path) }.from(true).to(false)
    end

    it "no-ops gracefully when the file does not exist" do
      bundle.update_columns(composite_cover_path: "composites/custom-9999.jpg")
      expect { bundle.destroy! }.not_to raise_error
    end
  end
end
