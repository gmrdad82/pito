require "rails_helper"

RSpec.describe Footage, type: :model do
  describe "associations" do
    subject { build(:footage) }
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:game).optional }
    it { is_expected.to belong_to(:tenant).optional }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:kind).with_values(a_roll: 0, b_roll: 1) }
    it { is_expected.to define_enum_for(:source).with_values(obs: 0, camera: 1) }
    it { is_expected.to define_enum_for(:orientation).with_values(landscape: 0, portrait: 1) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:local_path) }
    it { is_expected.to validate_presence_of(:filename) }
    it { is_expected.to validate_inclusion_of(:bit_depth).in_array([ 8, 10, 12 ]) }

    describe "local_path uniqueness scoped to tenant" do
      it "rejects a duplicate local_path within the same tenant" do
        tenant = create(:tenant)
        project = create(:project, tenant: tenant)
        create(:footage, project: project, local_path: "/tmp/x.mp4", filename: "x.mp4")
        dup = build(:footage, project: project, local_path: "/tmp/x.mp4", filename: "x.mp4")
        expect(dup).not_to be_valid
        expect(dup.errors[:local_path]).to be_present
      end

      it "permits the same local_path across tenants" do
        first_tenant = create(:tenant)
        second_tenant = create(:tenant)
        first_project = create(:project, tenant: first_tenant)
        second_project = create(:project, tenant: second_tenant)
        create(:footage, project: first_project, local_path: "/tmp/x.mp4", filename: "x.mp4")
        sibling = build(:footage, project: second_project, local_path: "/tmp/x.mp4", filename: "x.mp4")
        expect(sibling).to be_valid
      end
    end

    describe "platform / game coupling" do
      let(:tenant) { create(:tenant) }
      let(:project) { create(:project, tenant: tenant) }
      let(:game) do
        create(:game, tenant: tenant,
                      platforms: [ { "platform" => "PS5", "owned" => true, "recorded_on" => true } ])
      end

      it "requires platform when game_id is set" do
        footage = build(:footage, project: project, game: game, platform: nil)
        expect(footage).not_to be_valid
        expect(footage.errors[:platform]).to be_present
      end

      it "rejects a platform that is not in the game's allowlist" do
        footage = build(:footage, project: project, game: game, platform: "PC")
        expect(footage).not_to be_valid
        expect(footage.errors[:platform]).to include(/must be one of the game's platforms/)
      end

      it "accepts a platform present in the game's allowlist" do
        footage = build(:footage, project: project, game: game, platform: "PS5")
        expect(footage).to be_valid
      end

      it "ignores platform validation when game_id is nil" do
        footage = build(:footage, project: project, game: nil, platform: nil)
        expect(footage).to be_valid
      end
    end

    describe "commentary track consistency" do
      let(:project) { create(:project) }

      it "accepts has_commentary_track=true with audio_track_count >= 2" do
        footage = build(:footage, project: project,
                                  audio_track_count: 2, has_commentary_track: true)
        expect(footage).to be_valid
      end

      it "rejects has_commentary_track=true with audio_track_count < 2" do
        footage = build(:footage, project: project,
                                  audio_track_count: 1, has_commentary_track: true)
        expect(footage).not_to be_valid
      end

      it "ignores the rule when audio_track_count is nil" do
        footage = build(:footage, project: project,
                                  audio_track_count: nil, has_commentary_track: true)
        expect(footage).to be_valid
      end
    end
  end

  describe "tenant_id denormalization" do
    it "fills tenant_id from the project on save" do
      tenant = create(:tenant)
      project = create(:project, tenant: tenant)
      footage = build(:footage, project: project, tenant: nil)
      expect(footage.valid?).to be(true)
      expect(footage.tenant_id).to eq(tenant.id)
    end
  end

  # Phase 4 Wave 2 — `/projects` index revamp. The project row's
  # `footages_count` is the source of truth for both the display and the
  # SQL-side sort, so the counter must increment on create and decrement on
  # destroy.
  describe "counter_cache on project" do
    let(:project) { create(:project) }

    it "increments project.footages_count when a footage is created" do
      expect {
        create(:footage, project: project, tenant: project.tenant)
      }.to change { project.reload.footages_count }.from(0).to(1)
    end

    it "decrements project.footages_count when a footage is destroyed" do
      footage = create(:footage, project: project, tenant: project.tenant)
      project.reload
      expect(project.footages_count).to eq(1)

      expect {
        footage.destroy!
      }.to change { project.reload.footages_count }.from(1).to(0)
    end
  end
end
