require "rails_helper"

# Phase 7.5 §11g — Channel Change History HTML view spec.
RSpec.describe "channels/change_logs/index.html.erb", type: :view do
  let(:user)    { create(:user, username: "owner_logs") }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           title: "Cool Channel")
  end

  def assign_defaults(logs:, page: 1, total_pages: 1, total: nil, per_page: 50)
    assign(:channel, channel)
    assign(:logs, logs)
    assign(:page, page)
    assign(:total_pages, total_pages)
    assign(:total, total || logs.size)
    assign(:per_page, per_page)

    # The `url_for(page: ...)` helper inside the template relies on the
    # current request's path-parameter context (controller + action +
    # channel_id) to resolve the route. Set them explicitly so the
    # pagination links can be generated in isolation.
    controller.request.path_parameters = {
      controller: "channels/change_logs",
      action: "index",
      channel_id: channel.to_param
    }
  end

  describe "empty state" do
    before { assign_defaults(logs: []) }

    it "renders the muted `no changes yet` line" do
      render
      expect(rendered).to include("no changes yet")
    end

    it "does not render a table" do
      render
      expect(rendered).not_to include("<thead>")
    end

    it "does not render pagination links" do
      render
      expect(rendered).not_to match(/>\s*previous\s*</)
      expect(rendered).not_to match(/>\s*next\s*</)
    end
  end

  describe "non-empty state" do
    let(:log) do
      build_stubbed(:channel_change_log,
                    channel: channel,
                    changed_by_user: user,
                    field: "title",
                    old_value: "Old title",
                    new_value: "New title",
                    changed_at: 2.hours.ago)
    end

    before { assign_defaults(logs: [ log ]) }

    it "renders the H1 with the display title" do
      render
      expect(rendered).to include("change history")
      expect(rendered).to include("Cool Channel")
    end

    # 2026-05-11 — the explanatory lead paragraph was dropped per user
    # direction. The H1 + table communicate the read-only nature on
    # their own.
    it "does NOT render the dropped lead paragraph" do
      render
      expect(rendered).not_to include("title and handle edits are appended here automatically.")
      expect(rendered).not_to include("pito does not edit or delete past entries.")
    end

    it "wraps the body in pane--standalone" do
      render
      expect(rendered).to include("pane pane--standalone")
    end

    it "renders the four column headers" do
      render
      expect(rendered).to include(">field<")
      expect(rendered).to match(/old .* new/i)
      expect(rendered).to include("changed at")
      expect(rendered).to include("changed by")
    end

    it "renders the field value" do
      render
      expect(rendered).to include(">title<")
    end

    it "renders old and new values" do
      render
      expect(rendered).to include("Old title")
      expect(rendered).to include("New title")
    end

    it "renders a <time> element with title= absolute UTC" do
      render
      expect(rendered).to match(/<time[^>]+title="\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC"/)
    end

    it "renders relative time text" do
      render
      expect(rendered).to match(/about \d+ hours? ago/)
    end

    it "renders the changed_by user username" do
      render
      expect(rendered).to include("owner_logs")
    end
  end

  describe "system rendering for null FK" do
    let(:log) do
      build_stubbed(:channel_change_log,
                    channel: channel,
                    changed_by_user: nil,
                    field: "handle",
                    old_value: nil,
                    new_value: "@new",
                    changed_at: 1.hour.ago)
    end

    before { assign_defaults(logs: [ log ]) }

    it "renders `system` (muted) when the FK is null" do
      render
      expect(rendered).to include("system")
      expect(rendered).to include("text-muted")
    end

    it "renders em-dash for nil old_value" do
      render
      expect(rendered).to include("&mdash;").or include("—")
    end
  end

  describe "pagination" do
    let(:logs) { Array.new(50) { build_stubbed(:channel_change_log, channel: channel, changed_by_user: user) } }

    it "renders [previous] and [next] when on a middle page" do
      assign_defaults(logs: logs, page: 2, total_pages: 3, total: 150)
      render
      expect(rendered).to match(/>\s*previous\s*</)
      expect(rendered).to match(/>\s*next\s*</)
      expect(rendered).to include("page 2 / 3")
    end

    it "renders only [next] on page 1" do
      assign_defaults(logs: logs, page: 1, total_pages: 3, total: 150)
      render
      expect(rendered).not_to match(/>\s*previous\s*</)
      expect(rendered).to match(/>\s*next\s*</)
    end

    it "renders only [previous] on the last page" do
      assign_defaults(logs: logs, page: 3, total_pages: 3, total: 150)
      render
      expect(rendered).to match(/>\s*previous\s*</)
      expect(rendered).not_to match(/>\s*next\s*</)
    end

    it "hides pagination entirely when only one page" do
      assign_defaults(logs: logs, page: 1, total_pages: 1, total: 50)
      render
      expect(rendered).not_to match(/>\s*previous\s*</)
      expect(rendered).not_to match(/>\s*next\s*</)
      expect(rendered).not_to include("page 1 / 1")
    end
  end
end
