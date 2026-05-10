require "rails_helper"

# Phase 8 — tenant drop. Footage no longer carries a tenant; local_path
# uniqueness is install-wide.
RSpec.describe Footage, type: :model do
  describe "associations" do
    subject { build(:footage) }
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:game).optional }

    it "does not declare a tenant association" do
      expect(Footage.reflect_on_association(:tenant)).to be_nil
    end
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

    describe "local_path uniqueness (install-wide)" do
      it "rejects a duplicate local_path install-wide" do
        project = create(:project)
        create(:footage, project: project, local_path: "/tmp/x.mp4", filename: "x.mp4")
        dup = build(:footage, project: project, local_path: "/tmp/x.mp4", filename: "x.mp4")
        expect(dup).not_to be_valid
        expect(dup.errors[:local_path]).to be_present
      end

      it "rejects a duplicate local_path even across different projects" do
        project_a = create(:project)
        project_b = create(:project)
        create(:footage, project: project_a, local_path: "/tmp/x.mp4", filename: "x.mp4")
        sibling = build(:footage, project: project_b, local_path: "/tmp/x.mp4", filename: "x.mp4")
        expect(sibling).not_to be_valid
      end
    end

    describe "platform / game coupling" do
      let(:project) { create(:project) }
      let(:game) do
        create(:game, platforms: [ { "platform" => "PS5", "owned" => true, "recorded_on" => true } ])
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

  describe "counter_cache on project" do
    let(:project) { create(:project) }

    it "increments project.footages_count when a footage is created" do
      expect {
        create(:footage, project: project)
      }.to change { project.reload.footages_count }.from(0).to(1)
    end

    it "decrements project.footages_count when a footage is destroyed" do
      footage = create(:footage, project: project)
      project.reload
      expect(project.footages_count).to eq(1)

      expect {
        footage.destroy!
      }.to change { project.reload.footages_count }.from(1).to(0)
    end
  end

  describe "project.footage_duration_seconds aggregate cache" do
    let(:project) { create(:project) }

    it "increases by a new footage's duration on create" do
      expect {
        create(:footage, project: project, duration_seconds: 600)
      }.to change { project.reload.footage_duration_seconds }.from(0).to(600)
    end

    it "ignores nil-duration footages (treats nil as 0)" do
      create(:footage, project: project, duration_seconds: 600)
      project.reload
      expect {
        create(:footage, project: project, duration_seconds: nil)
      }.not_to change { project.reload.footage_duration_seconds }
    end

    it "decreases by a destroyed footage's duration" do
      a = create(:footage, project: project, duration_seconds: 600)
      create(:footage, project: project, duration_seconds: 200)
      project.reload
      expect(project.footage_duration_seconds).to eq(800)

      expect {
        a.destroy!
      }.to change { project.reload.footage_duration_seconds }.from(800).to(200)
    end

    it "recomputes when an existing footage's duration changes" do
      footage = create(:footage, project: project, duration_seconds: 600)
      project.reload
      expect(project.footage_duration_seconds).to eq(600)

      footage.update!(duration_seconds: 900)
      expect(project.reload.footage_duration_seconds).to eq(900)
    end

    it "does not recompute when an unrelated column changes" do
      footage = create(:footage, project: project, duration_seconds: 600)
      project.reload
      expect(project.footage_duration_seconds).to eq(600)

      expect {
        footage.update!(filename: "renamed.mp4")
      }.not_to change { project.reload.footage_duration_seconds }
    end

    it "refreshes both projects when a footage moves between projects" do
      old_project = project
      new_project = create(:project)
      footage = create(:footage, project: old_project, duration_seconds: 600)
      old_project.reload
      expect(old_project.footage_duration_seconds).to eq(600)

      footage.update!(project: new_project)
      expect(old_project.reload.footage_duration_seconds).to eq(0)
      expect(new_project.reload.footage_duration_seconds).to eq(600)
    end

    it "no-ops cleanly when the parent project is destroyed (cascade)" do
      create(:footage, project: project, duration_seconds: 600)
      project.reload
      expect { project.destroy! }.not_to raise_error
    end
  end
end
