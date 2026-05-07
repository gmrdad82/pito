require "rails_helper"

# Phase 4 §14 step 8 — route shells must resolve before Phase B's nav edit
# fires. Phase A doesn't ship the controller bodies (other than the importer
# download), so we restrict to routing.spec assertions: the named helpers
# resolve and `bin/rails routes` would render the rows.
RSpec.describe "Project Workspace routes", type: :routing do
  # `route_to` would force-load the controller classes. Phase A only ships
  # route shells (controllers land in Phase B), so we assert via the URL
  # helpers and recognize_path: the routes table contains the entries we
  # need, named helpers resolve, but no constant gets autoloaded.
  let(:helpers) { Rails.application.routes.url_helpers }

  describe "named path helpers (Phase A § 14 step 8)" do
    it "exposes projects_path -> /projects" do
      expect(helpers.projects_path).to eq("/projects")
    end

    it "exposes project_path(id) -> /projects/:id" do
      expect(helpers.project_path(42)).to eq("/projects/42")
    end

    %w[collections games footages notes timelines].each do |resource|
      it "exposes #{resource}_path -> /#{resource}" do
        expect(helpers.public_send("#{resource}_path")).to eq("/#{resource}")
      end
    end

    it "exposes footage_importer_download_path -> /footage/importer/download" do
      expect(helpers.footage_importer_download_path)
        .to eq("/footage/importer/download")
    end

    it "exposes the nested API helper api_project_footages_path" do
      expect(helpers.api_project_footages_path(7))
        .to eq("/api/projects/7/footages")
    end

    it "exposes the symmetric API member helper api_footage_path" do
      # Phase 5.5 — `/api/footages/:id` for PATCH/DELETE under
      # `Api::FootagesController` so the importer's URL surface is symmetric.
      expect(helpers.api_footage_path(9)).to eq("/api/footages/9")
    end
  end

  describe "routes table introspection" do
    # Controllers (other than the importer-download stub) land in Phase B,
    # so we cannot use route_to / recognize_path here — both force-load the
    # controller class. We assert the routes table contains the expected
    # rows by walking Rails.application.routes.routes directly.
    let(:route_names) do
      Rails.application.routes.routes.map(&:name).compact
    end

    it "registers the projects resource" do
      expect(route_names).to include("projects", "project")
    end

    it "registers the rest of the new resources" do
      expect(route_names).to include(
        "collections", "collection",
        "games", "game",
        "footages", "footage",
        "notes", "note",
        "timelines", "timeline"
      )
    end

    it "registers the importer download stub" do
      expect(route_names).to include("footage_importer_download")
    end

    it "registers the nested API api_project_footages route" do
      expect(route_names).to include("api_project_footages")
    end

    it "registers the symmetric API member route api_footage" do
      # Phase 5.5 — symmetric `/api/footages/:id` PATCH/DELETE.
      expect(route_names).to include("api_footage")
    end
  end
end
