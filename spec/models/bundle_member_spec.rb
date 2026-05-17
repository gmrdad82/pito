require "rails_helper"

RSpec.describe BundleMember, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:bundle) }
    it { is_expected.to belong_to(:game) }
  end

  describe "validations" do
    let(:bundle) { create(:bundle) }
    let(:game)   { create(:game) }

    it "enforces (bundle_id, game_id) uniqueness" do
      bundle.bundle_members.create!(game: game)
      dup = bundle.bundle_members.build(game: game)
      expect(dup).not_to be_valid
      expect(dup.errors[:game_id]).to be_present
    end

    it "validates position is a non-negative integer" do
      bm = bundle.bundle_members.build(game: game, position: -1)
      expect(bm).not_to be_valid
      expect(bm.errors[:position]).to be_present
    end
  end

  describe "before_validation :assign_position" do
    let(:bundle) { create(:bundle) }

    it "sets position to 0 on the first member" do
      g = create(:game)
      bm = bundle.bundle_members.create!(game: g)
      expect(bm.position).to eq(0)
    end

    it "sets position to MAX(position) + 1 on subsequent members" do
      g1 = create(:game)
      g2 = create(:game)
      bundle.bundle_members.create!(game: g1)
      bm = bundle.bundle_members.create!(game: g2)
      expect(bm.position).to eq(1)
    end

    it "respects an explicit non-zero position on create" do
      g = create(:game)
      bm = bundle.bundle_members.create!(game: g, position: 42)
      expect(bm.position).to eq(42)
    end
  end

  describe "callbacks" do
    let(:bundle) { create(:bundle) }
    let(:game)   { create(:game) }

    it "after_create_commit enqueues BundleCoverBuild" do
      BundleCoverBuild.clear
      bundle.bundle_members.create!(game: game)
      expect(BundleCoverBuild.jobs.map { |j| j["args"].first })
        .to include(bundle.id)
    end

    it "after_destroy_commit enqueues BundleCoverBuild" do
      bm = bundle.bundle_members.create!(game: game)
      BundleCoverBuild.clear
      bm.destroy!
      expect(BundleCoverBuild.jobs.map { |j| j["args"].first })
        .to include(bundle.id)
    end
  end

  describe "cascade-on-delete from Bundle" do
    it "removes BundleMember rows but preserves Games" do
      bundle = create(:bundle)
      g1 = create(:game)
      g2 = create(:game)
      bundle.bundle_members.create!(game: g1)
      bundle.bundle_members.create!(game: g2)

      expect { bundle.destroy! }.to change(BundleMember, :count).by(-2)
      expect(Game.exists?(g1.id)).to be(true)
      expect(Game.exists?(g2.id)).to be(true)
    end
  end

  describe "cascade-on-delete from Game" do
    it "removes BundleMember rows but preserves the Bundle" do
      bundle = create(:bundle)
      g = create(:game)
      bundle.bundle_members.create!(game: g)

      expect { g.destroy! }.to change(BundleMember, :count).by(-1)
      expect(Bundle.exists?(bundle.id)).to be(true)
    end
  end
end
