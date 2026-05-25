require "rails_helper"

# Sessions::TableComponent spec.
#
# Key contract under test: the defaultHeader `<tr>` must NOT carry
# `data-tui-focusable` after the FB-146 / FB-PURPLE-REGRESSION even-row
# cursor fix. Adding that attr to the header row shifts every body row's
# focus-stop index by one, which makes even body rows miss the cursor
# tint. The header Stimulus wiring (`data-sessions-bulk-revoke-target=
# "defaultHeader"`) must still be present — it drives header swap.
#
# Fixtures: `instance_double(Session, ...)` — no DB hit, no factory.
# The component is pure-input-driven (`current_session_id:` injected).
RSpec.describe Sessions::TableComponent, type: :component do
  def make_session(id:, device: "linux", browser: "chrome", ip: "127.0.0.1",
                   last_activity_at: 1.hour.ago, created_at: 1.day.ago,
                   user_agent: "Mozilla/5.0")
    instance_double(
      Session,
      id: id,
      device: device,
      browser: browser,
      ip: ip,
      last_activity_at: last_activity_at,
      created_at: created_at,
      user_agent: user_agent
    )
  end

  let(:session_a) { make_session(id: 1) }
  let(:session_b) { make_session(id: 2) }
  let(:sessions)  { [ session_a, session_b ] }

  subject(:rendered) do
    render_inline(
      described_class.new(
        sessions: sessions,
        sessions_sort: "last_activity",
        sessions_dir: "desc",
        current_session_id: nil,
        frame: "sessions_panel"
      )
    )
  end

  # -----------------------------------------------------------------------
  # Core focusable contract — the header must be invisible to the cursor
  # -----------------------------------------------------------------------

  describe "defaultHeader <tr> focusable contract" do
    it "preserves the Stimulus bulk-revoke target on the defaultHeader row" do
      default_header = rendered.css("thead tr[data-sessions-bulk-revoke-target='defaultHeader']").first
      expect(default_header).to be_present
    end

    it "does NOT carry data-tui-focusable on the defaultHeader <tr>" do
      default_header = rendered.css("thead tr[data-sessions-bulk-revoke-target='defaultHeader']").first
      expect(default_header["data-tui-focusable"]).to be_nil
    end

    it "does NOT carry data-tui-focusable-style on the defaultHeader <tr>" do
      default_header = rendered.css("thead tr[data-sessions-bulk-revoke-target='defaultHeader']").first
      expect(default_header["data-tui-focusable-style"]).to be_nil
    end
  end

  # -----------------------------------------------------------------------
  # Body rows carry the correct focusable attrs
  # -----------------------------------------------------------------------

  describe "body row focusable wiring" do
    it "emits data-tui-focusable on every body <tr>" do
      rows = rendered.css("tbody tr.tui-table__row")
      expect(rows.length).to eq(2)
      rows.each { |row| expect(row["data-tui-focusable"]).to be_present }
    end

    it "keys body rows as row_<id> matching the #focusables contract" do
      rows = rendered.css("tbody tr.tui-table__row")
      expect(rows[0]["data-tui-focusable"]).to eq("row_1")
      expect(rows[1]["data-tui-focusable"]).to eq("row_2")
    end

    it "marks every body row with focusable-style=row" do
      rows = rendered.css("tbody tr.tui-table__row")
      rows.each { |row| expect(row["data-tui-focusable-style"]).to eq("row") }
    end
  end

  # -----------------------------------------------------------------------
  # #focusables Ruby contract — select_all is slot 0; body rows follow
  # -----------------------------------------------------------------------

  describe "#focusables" do
    subject(:component) do
      described_class.new(
        sessions: sessions,
        sessions_sort: "last_activity",
        sessions_dir: "desc",
        current_session_id: nil
      )
    end

    it "returns select_all as the first focusable entry" do
      expect(component.focusables.first).to eq({ key: "select_all", style: :row })
    end

    it "returns one entry per session after the select_all slot" do
      expect(component.focusables.length).to eq(3) # 1 select_all + 2 sessions
    end

    it "keys session focusables as row_<id>" do
      keys = component.focusables.drop(1).map { |f| f[:key] }
      expect(keys).to eq([ "row_1", "row_2" ])
    end
  end

  # -----------------------------------------------------------------------
  # Empty-state branch — no table rendered, no focusable attrs emitted
  # -----------------------------------------------------------------------

  describe "empty state" do
    subject(:rendered) do
      render_inline(
        described_class.new(
          sessions: [],
          sessions_sort: "last_activity",
          sessions_dir: "desc",
          current_session_id: nil
        )
      )
    end

    it "renders no <table>" do
      expect(rendered.css("table").length).to eq(0)
    end

    it "emits the empty-state paragraph" do
      p = rendered.css("p.text-muted").first
      expect(p).to be_present
      expect(p.text.strip).to eq("no active sessions.")
    end
  end
end
