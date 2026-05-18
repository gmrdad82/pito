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
