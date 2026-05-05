require "rails_helper"

RSpec.describe "Projects", type: :request do
  describe "GET /projects" do
    it "returns 200" do
      get projects_path
      expect(response).to have_http_status(:ok)
    end

    it "shows the add bracketed link in the projects header" do
      # Item 2 — `[ new project ]` collapsed to `[ add ]` since the
      # surrounding `<h1>projects</h1>` already establishes the noun.
      get projects_path
      expect(response.body).to include('class="bl">add</span>')
    end

    context "with projects" do
      let!(:project) { create(:project) }

      it "displays project names" do
        get projects_path
        expect(response.body).to include(project.name)
      end
    end

    describe "bulk-select picker markup" do
      it "wires the bulk-select Stimulus controller with project delete type" do
        get projects_path
        expect(response.body).to include('data-controller="bulk-select"')
        expect(response.body).to include('data-bulk-select-entity-name-value="projects"')
        expect(response.body).to include('data-bulk-select-delete-type-value="project"')
      end

      it "omits the panes-related data values (no multi-pane open on /projects)" do
        get projects_path
        expect(response.body).not_to include("data-bulk-select-max-panes-value")
        expect(response.body).not_to include("data-bulk-select-panes-path-value")
      end

      context "with projects" do
        let!(:project_a) { create(:project, name: "Alpha") }
        let!(:project_b) { create(:project, name: "Bravo") }

        it "omits the openHint and openAction targets (panes-specific, controller guards them)" do
          get projects_path
          expect(response.body).not_to include('data-bulk-select-target="openHint"')
          expect(response.body).not_to include('data-bulk-select-target="openAction"')
        end

        it "omits the permanently-hidden wrapper used as a workaround in the previous markup" do
          get projects_path
          expect(response.body).not_to include('hidden style="display: none;"')
        end
      end

      it "renders the [ bulk ] toggle link" do
        get projects_path
        expect(response.body).to include('data-bulk-select-target="bulkToggle"')
        expect(response.body).to include("click-&gt;bulk-select#enterBulk")
      end

      context "with projects" do
        let!(:project_a) { create(:project, name: "Alpha") }
        let!(:project_b) { create(:project, name: "Bravo") }

        it "renders the bulk-mode action toolbar (hidden by default)" do
          get projects_path
          expect(response.body).to include('data-bulk-select-target="actions"')
          expect(response.body).to include('data-bulk-select-target="count"')
          expect(response.body).to include('data-bulk-select-target="deleteAction"')
        end

        it "renders the bulk-select header + per-row checkbox columns (hidden by default)" do
          get projects_path
          expect(response.body).to include('data-bulk-select-target="headerCheckbox"')
          expect(response.body).to include('data-bulk-select-target="bulkCol"')
          # one checkbox per project row
          expect(response.body.scan('data-bulk-select-target="checkbox"').size).to eq(2)
        end

        it "wires the cancel link to exitBulk" do
          get projects_path
          expect(response.body).to include("click-&gt;bulk-select#exitBulk")
        end

        # Phase B — leading-separator pattern. Each `.action` span carries
        # its own `.action-sep` dot; the JS controller hides the dot on
        # whichever action is first-visible, so the toolbar never starts
        # with a dangling `· [ cancel ]`.
        it "renders the bulk-toolbar leading-separator pattern" do
          get projects_path
          expect(response.body).to include("bulk-toolbar")
          # Every action span has an `.action-sep` `&middot;` baked in.
          expect(response.body).to match(/<span class="action-sep" hidden>/)
        end

        it "ships with every leading separator hidden in the static initial render" do
          get projects_path
          # The server-rendered initial state must NOT show a `&middot;`
          # before `[ cancel ]`. Parse the actions container; assert that
          # every `.action-sep` carries the `hidden` attribute (the JS
          # controller only flips them when the toolbar transitions).
          html = Nokogiri::HTML.fragment(response.body)
          actions = html.css('[data-bulk-select-target="actions"]').first
          expect(actions).not_to be_nil, "expected the bulk-select actions container in markup"
          separators = actions.css(".action-sep")
          expect(separators).not_to be_empty, "expected at least one .action-sep dot inside the toolbar"
          separators.each do |sep|
            expect(sep["hidden"]).not_to be_nil,
              "expected .action-sep to ship with the `hidden` attribute, got: #{sep.to_html}"
          end
        end
      end
    end
  end

  describe "POST /projects (default-create)" do
    it "creates a project with the default name and redirects to show" do
      expect {
        post projects_path
      }.to change(Project, :count).by(1)

      project = Project.last
      expect(project.name).to eq("Untitled project")
      expect(response).to redirect_to(project_path(project))
    end

    it "renders the show page successfully after the redirect" do
      post projects_path
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Untitled project")
      expect(response.body).to include("footage")
      expect(response.body).to include("notes")
      expect(response.body).to include("timelines")
    end
  end

  describe "GET /projects/:id" do
    let!(:project) { create(:project) }

    it "renders the three panes" do
      get project_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("footage")
      expect(response.body).to include("notes")
      expect(response.body).to include("timelines")
    end

    it "renders three pane-wrapper divs" do
      get project_path(project)
      expect(response.body.scan(/class="pane-wrapper"/).size).to eq(3)
    end

    it "renders [edit] and [delete] in the breadcrumb actions" do
      get project_path(project)
      expect(response.body).to include('class="bl">edit</span>')
      expect(response.body).to include('class="bl">delete</span>')
      expect(response.body).to include(edit_project_path(project))
    end

    it "does not render an inline edit form on the show page" do
      get project_path(project)
      # No name input field on show — editing happens on /projects/:id/edit
      expect(response.body).not_to include('name="project[name]"')
    end
  end

  describe "GET /projects/:id/edit" do
    let!(:project) { create(:project, name: "Some project") }

    it "returns 200 and renders a form with the name field" do
      get edit_project_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="project[name]"')
      expect(response.body).to include("Some project")
      # cancel link points back to show
      expect(response.body).to include(project_path(project))
    end
  end

  describe "PATCH /projects/:id (rename)" do
    let!(:project) { create(:project, name: "Untitled project") }

    it "renames the project" do
      patch project_path(project), params: { project: { name: "My new project" } }
      expect(project.reload.name).to eq("My new project")
      expect(response).to redirect_to(project_path(project))
    end
  end

  describe "DELETE /projects/:id" do
    let!(:project) { create(:project) }

    it "destroys the project" do
      expect {
        delete project_path(project)
      }.to change(Project, :count).by(-1)
      expect(response).to redirect_to(projects_path)
    end
  end
end
