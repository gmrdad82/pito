require "rails_helper"

RSpec.describe Settings::Stack::Sidekiq::CountersComponent, type: :component do
  # Canonical shape produced by
  # `SettingsController#sidekiq_breakdown_for_settings_pane` — an Array
  # of `{ label:, count: }` hashes, NOT a flat keyword hash.
  let(:breakdown) do
    [
      { label: "processed", count: 42_000 },
      { label: "failed",    count: 18 },
      { label: "busy",      count: 3 },
      { label: "scheduled", count: 5 },
      { label: "enqueued",  count: 12 },
      { label: "retry",     count: 0 },
      { label: "dead",      count: 2 }
    ]
  end

  describe "structure (alignment invariant + live-update targets)" do
    before { render_inline(described_class.new(breakdown: breakdown)) }

    it "renders 5 num column headers in the queue grid (alignment invariant)" do
      # The queue table's <thead> has 5 num-class <th> cells — busy,
      # scheduled, enqueued, retry, dead. The lifetime table has 5 too
      # (2 labeled + 3 spacer), so total across both tables is 10.
      expect(page).to have_css("th.num", count: 10)
    end

    it "wires the successful cell to the live-update target" do
      expect(page).to have_css('td.num[data-stack-stats-live-target="successful"]')
    end

    it "wires the failed cell to the live-update target" do
      expect(page).to have_css('td.num[data-stack-stats-live-target="failed"]')
    end

    it "wires every queue state cell to its live-update target" do
      %w[busy scheduled enqueued retry dead].each do |state|
        expect(page).to have_css(%(td.num[data-stack-stats-live-target="#{state}"]))
      end
    end

    it "shares the 5-col grid across both tables (2 colgroups x 5 cols = 10)" do
      expect(page).to have_css("colgroup col", count: 10)
    end

    it "renders both tables with table-layout: fixed (the shared-grid invariant)" do
      expect(page).to have_css('table.stack-table[style*="table-layout: fixed"]', count: 2)
    end

    it "renders the successful count with thousand-separator formatting" do
      expect(page).to have_css(
        'td.num[data-stack-stats-live-target="successful"]', text: "42,000"
      )
    end

    it "renders the failed count" do
      expect(page).to have_css(
        'td.num[data-stack-stats-live-target="failed"]', text: "18"
      )
    end

    it "renders queue state counts in their wired cells" do
      expect(page).to have_css('td.num[data-stack-stats-live-target="busy"]', text: "3")
      expect(page).to have_css('td.num[data-stack-stats-live-target="enqueued"]', text: "12")
      expect(page).to have_css('td.num[data-stack-stats-live-target="dead"]', text: "2")
    end

    it "places successful under enqueued (col 3) and failed under dead (col 5)" do
      # Lifetime row: cells 1, 2, 4 are spacer (empty); cells 3, 5 carry data.
      lifetime_table = page.find('table.stack-table', match: :first)
      cells = lifetime_table.all('tbody tr td.num', visible: :all)
      expect(cells.size).to eq(5)
      expect(cells[0].text).to eq("")
      expect(cells[1].text).to eq("")
      expect(cells[2]["data-stack-stats-live-target"]).to eq("successful")
      expect(cells[3].text).to eq("")
      expect(cells[4]["data-stack-stats-live-target"]).to eq("failed")
    end
  end

  describe "missing-state fallback" do
    it "renders a dash when a state's count is missing from the breakdown" do
      render_inline(described_class.new(breakdown: [
        { label: "busy", count: 1 }
        # processed / failed / scheduled / enqueued / retry / dead are absent
      ]))
      expect(page).to have_css(
        'td.num[data-stack-stats-live-target="successful"]', text: "—"
      )
      expect(page).to have_css(
        'td.num[data-stack-stats-live-target="failed"]', text: "—"
      )
      expect(page).to have_css(
        'td.num[data-stack-stats-live-target="retry"]', text: "—"
      )
    end
  end

  # Beta 4 F3-D — per-state tonal class on each cell. The rules mirror
  # the status-bar Sidekiq segment (`.sb-sk-cell.sk-b` etc.) and reuse
  # the `tui-chip--*` color modifiers so the cell takes the same color
  # token surface as the canonical chip primitive — no new CSS class
  # family is needed.
  describe "per-state color rules" do
    before { render_inline(described_class.new(breakdown: breakdown)) }

    it "colors a non-zero busy count green via `tui-chip--success`" do
      expect(page).to have_css(
        'td.num.tui-chip--success[data-stack-stats-live-target="busy"]', text: "3"
      )
    end

    it "colors a non-zero enqueued count orange via `tui-chip--warn`" do
      expect(page).to have_css(
        'td.num.tui-chip--warn[data-stack-stats-live-target="enqueued"]', text: "12"
      )
    end

    it "colors a non-zero dead count pink via `tui-chip--danger`" do
      expect(page).to have_css(
        'td.num.tui-chip--danger[data-stack-stats-live-target="dead"]', text: "2"
      )
    end

    it "colors a non-zero failed count pink via `tui-chip--danger`" do
      expect(page).to have_css(
        'td.num.tui-chip--danger[data-stack-stats-live-target="failed"]', text: "18"
      )
    end

    it "keeps scheduled muted via `tui-chip--neutral` even when non-zero" do
      expect(page).to have_css(
        'td.num.tui-chip--neutral[data-stack-stats-live-target="scheduled"]', text: "5"
      )
    end

    it "rolls back to muted via `tui-chip--neutral` when a count is zero" do
      # `retry` in the breakdown above is 0 — must NOT carry the danger
      # class, must carry the neutral class.
      expect(page).to have_css(
        'td.num.tui-chip--neutral[data-stack-stats-live-target="retry"]'
      )
      expect(page).not_to have_css(
        'td.num.tui-chip--danger[data-stack-stats-live-target="retry"]'
      )
    end
  end

  describe "#color_class_for" do
    let(:component) { described_class.new(breakdown: breakdown) }

    it "returns the warn modifier for non-zero enqueued" do
      expect(component.color_class_for("enqueued")).to eq("tui-chip--warn")
    end

    it "returns the danger modifier for non-zero dead" do
      expect(component.color_class_for("dead")).to eq("tui-chip--danger")
    end

    it "returns the neutral modifier for a zero-valued state" do
      expect(component.color_class_for("retry")).to eq("tui-chip--neutral")
    end

    it "returns the neutral modifier for an absent state" do
      empty_component = described_class.new(breakdown: [])
      expect(empty_component.color_class_for("busy")).to eq("tui-chip--neutral")
    end
  end
end
