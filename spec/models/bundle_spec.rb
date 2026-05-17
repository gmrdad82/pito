require "rails_helper"

# Phase 14 §2 / Phase 27 follow-up (2026-05-17) — Bundle model spec.
# After the 2026-05-17 simplification a Bundle has only `name` (plus
# the composite-cover artifact columns). The legacy `bundle_type` /
# `igdb_source_*` enums and their validations are gone, so the
# corresponding describe blocks are removed.
RSpec.describe Bundle, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:bundle_members).dependent(:destroy) }
    it { is_expected.to have_many(:games).through(:bundle_members) }

    # Phase 14 §3 — video attribution links.
    it { is_expected.to have_many(:video_game_links).dependent(:destroy) }
    it { is_expected.to have_many(:videos).through(:video_game_links) }

    it "orders bundle_members by position" do
      bundle = create(:bundle)
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
  end

  describe "#composite_cover_url" do
    it "returns nil when path blank" do
      expect(build(:bundle, composite_cover_path: nil).composite_cover_url).to be_nil
    end

    it "returns the well-formed /composites/... URL when path present" do
      bundle = build(:bundle, composite_cover_path: "composites/bundle-7.jpg")
      expect(bundle.composite_cover_url).to eq("/composites/bundle-7.jpg")
    end
  end

  describe "#needs_cover_rebuild?" do
    let(:bundle) { create(:bundle) }

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
      bundle.update_columns(composite_cover_path: "composites/bundle-#{bundle.id}.jpg",
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
    let(:bundle) { create(:bundle) }

    it "after_save enqueues BundleCoverBuild on create" do
      BundleCoverBuild.clear
      b = create(:bundle)
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
    let(:bundle) { create(:bundle) }

    it "removes the on-disk composite cover file if present" do
      path = Pito::AssetsRoot.path("composites", "bundle-#{bundle.id}.jpg")
      FileUtils.mkdir_p(path.dirname)
      File.write(path, "JPEG bytes")
      bundle.update_columns(composite_cover_path: "composites/bundle-#{bundle.id}.jpg")

      expect { bundle.destroy! }.to change { File.exist?(path) }.from(true).to(false)
    end

    it "no-ops gracefully when the file does not exist" do
      bundle.update_columns(composite_cover_path: "composites/bundle-9999.jpg")
      expect { bundle.destroy! }.not_to raise_error
    end
  end
end
