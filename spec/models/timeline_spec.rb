require "rails_helper"

RSpec.describe Timeline, type: :model do
  subject { build(:timeline) }

  describe "associations" do
    it { is_expected.to belong_to(:tenant) }
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:video).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_most(255) }
  end

  describe "default title" do
    it 'defaults to "Untitled timeline"' do
      tenant = create(:tenant)
      project = create(:project, tenant: tenant)
      timeline = Timeline.create!(tenant: tenant, project: project)
      expect(timeline.title).to eq("Untitled timeline")
    end
  end

  # Phase 4 Wave 2 — `/projects` index revamp. Mirrors footages_count /
  # notes_count: timeline lifecycle drives the project row's count column.
  describe "counter_cache on project" do
    let(:tenant)  { create(:tenant) }
    let(:project) { create(:project, tenant: tenant) }

    it "increments project.timelines_count when a timeline is created" do
      expect {
        create(:timeline, project: project, tenant: tenant)
      }.to change { project.reload.timelines_count }.from(0).to(1)
    end

    it "decrements project.timelines_count when a timeline is destroyed" do
      timeline = create(:timeline, project: project, tenant: tenant)
      project.reload
      expect(project.timelines_count).to eq(1)

      expect {
        timeline.destroy!
      }.to change { project.reload.timelines_count }.from(1).to(0)
    end
  end

  describe "aasm state machine" do
    let(:timeline) { create(:timeline) }

    it "starts in :editing" do
      expect(timeline.state).to eq("editing")
      expect(timeline).to be_editing
    end

    it "transitions editing -> exported via #export!" do
      timeline.export!
      expect(timeline.reload).to be_exported
    end

    it "transitions exported -> uploaded via #upload!" do
      timeline.export!
      timeline.upload!
      expect(timeline.reload).to be_uploaded
    end

    it "rejects upload! from editing (must export first)" do
      expect { timeline.upload! }.to raise_error(AASM::InvalidTransition)
    end

    it "rejects export! from exported (no double-export)" do
      timeline.export!
      expect { timeline.export! }.to raise_error(AASM::InvalidTransition)
    end

    it "rejects export! from uploaded (no rewind)" do
      timeline.export!
      timeline.upload!
      expect { timeline.export! }.to raise_error(AASM::InvalidTransition)
    end
  end
end
