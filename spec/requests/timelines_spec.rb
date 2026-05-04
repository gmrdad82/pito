require "rails_helper"

RSpec.describe "Timelines", type: :request do
  let!(:project) { create(:project) }

  describe "POST /projects/:project_id/timelines" do
    it "default-creates a timeline" do
      expect {
        post project_timelines_path(project)
      }.to change(Timeline, :count).by(1)
      timeline = Timeline.last
      expect(timeline.title).to eq("Untitled timeline")
      expect(timeline.state).to eq("editing")
    end
  end

  describe "PATCH /timelines/:id (transitions)" do
    let!(:timeline) { create(:timeline, project: project) }

    it "rejects upload from editing state" do
      patch timeline_path(timeline), params: { transition: "upload", youtube_url: "https://youtu.be/dQw4w9WgXcQ" }
      expect(timeline.reload.state).to eq("editing")
      expect(flash[:alert]).to include("cannot upload")
    end

    it "exports from editing state" do
      patch timeline_path(timeline), params: { transition: "export" }
      expect(timeline.reload.state).to eq("exported")
    end
  end

  describe "DELETE /timelines/:id" do
    let!(:timeline) { create(:timeline, project: project) }

    it "destroys the timeline" do
      expect {
        delete timeline_path(timeline)
      }.to change(Timeline, :count).by(-1)
    end
  end
end
