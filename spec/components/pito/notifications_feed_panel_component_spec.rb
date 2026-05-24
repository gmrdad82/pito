require "rails_helper"

RSpec.describe Pito::NotificationsFeedPanelComponent, type: :component do
  # Helpers to build notification doubles without DB writes.
  # `dom_id(n)` calls `n.to_key` → `[n.id]` so we stub that too.
  def build_notification(id:, kind: "sync_error", title: "test", unread: true)
    n = instance_double(
      Notification,
      id: id,
      kind: kind,
      title: title,
      unread?: unread,
      read?: !unread,
      created_at: 2.hours.ago
    )
    allow(n).to receive(:to_model).and_return(n)
    allow(n).to receive(:persisted?).and_return(true)
    allow(n).to receive(:model_name).and_return(Notification.model_name)
    allow(n).to receive(:to_key).and_return([ id ])
    allow(n).to receive(:to_param).and_return(id.to_s)
    n
  end

  let(:notifications_relation) do
    rel = instance_double(ActiveRecord::Relation)
    allow(rel).to receive(:any?).and_return(false)
    allow(rel).to receive(:each).and_return([])
    allow(rel).to receive(:map).and_return([])
    rel
  end

  subject(:rendered) do
    render_inline(described_class.new(
      notifications: notifications_relation,
      filter: "all",
      unread_count: 0
    ))
  end

  let(:root) { rendered.css("section.pito-panel").first }

  # -----------------------------------------------------------------------
  # Panel chrome
  # -----------------------------------------------------------------------
  it "renders the canonical pito-panel section wrapper" do
    expect(root).to be_present
    expect(root["class"]).to include("pito-panel")
    expect(root["class"]).to include("pito-panel--notifications-feed")
  end

  it "renders the i18n title" do
    title = I18n.t("tui.home.panels.notifications_feed.title")
    expect(title).to eq("notifications")
    header = rendered.css(".pito-pane__title").first
    expect(header).to be_present
    expect(header.text.strip).to eq(title)
  end

  it "wires the tui-panel-cable Stimulus controller" do
    expect(root["data-controller"]).to include("tui-panel-cable")
  end

  it "emits the canonical cable name + screen data values" do
    expect(root["data-tui-panel-cable-name-value"]).to eq("notifications_feed")
    expect(root["data-tui-panel-cable-screen-value"]).to eq("home")
  end

  it "registers the panel as a tui-cursor target" do
    expect(root["data-tui-cursor-target"]).to eq("panel")
  end

  # -----------------------------------------------------------------------
  # Sync indicator
  # -----------------------------------------------------------------------
  describe "panel-level sync indicator" do
    it "renders the Tui::SyncIndicatorComponent targeting home.notifications_feed" do
      sync = rendered.css("button.tui-sync-word--target").first
      expect(sync).to be_present
      expect(sync["data-tui-sync-indicator-target-value"]).to eq("home.notifications_feed")
    end

    it "carries data-tui-focusable-key=notifications_feed_sync" do
      sync = rendered.css("button.tui-sync-word--target").first
      expect(sync["data-tui-focusable-key"]).to eq("notifications_feed_sync")
    end
  end

  # -----------------------------------------------------------------------
  # PANEL_NAME canonical contract
  # -----------------------------------------------------------------------
  describe "PANEL_NAME" do
    it "matches the canonical Pito::PanelChannel allowlist entry" do
      expect(described_class::PANEL_NAME).to eq(:notifications_feed)
      expect(Pito::PanelChannel::ALLOWED_PANELS).to include(described_class::PANEL_NAME.to_s)
    end
  end

  # -----------------------------------------------------------------------
  # Focusables contract
  # -----------------------------------------------------------------------
  describe "#focusables" do
    context "with no notifications" do
      it "includes sync and select_all keys only" do
        component = described_class.new(
          notifications: notifications_relation,
          filter: "all",
          unread_count: 0
        )
        # stub #notifications on the component instance
        allow(component).to receive(:notifications).and_return([])
        expect(component.focusables).to eq(%w[notifications_feed_sync select_all])
      end
    end

    context "with notifications" do
      it "appends row_<id> keys for each notification" do
        n1 = build_notification(id: 1)
        n2 = build_notification(id: 2)
        component = described_class.new(
          notifications: notifications_relation,
          filter: "all",
          unread_count: 0
        )
        allow(component).to receive(:notifications).and_return([ n1, n2 ])
        expect(component.focusables).to eq(%w[notifications_feed_sync select_all row_1 row_2])
      end
    end
  end

  # -----------------------------------------------------------------------
  # Filter: ?notifications_feed_filter=unread
  # -----------------------------------------------------------------------
  describe "filter state" do
    context "with filter=all" do
      subject(:rendered) do
        render_inline(described_class.new(
          notifications: notifications_relation,
          filter: "all",
          unread_count: 0
        ))
      end

      it "renders unchecked [ ] unread checkbox" do
        checkbox_span = rendered.css(".tui-checkbox").first
        expect(checkbox_span).to be_present
        expect(checkbox_span["class"]).not_to include("tui-checkbox--checked")
      end
    end

    context "with filter=unread" do
      subject(:rendered) do
        render_inline(described_class.new(
          notifications: notifications_relation,
          filter: "unread",
          unread_count: 3
        ))
      end

      it "renders checked [x] unread checkbox" do
        checkbox_span = rendered.css(".tui-checkbox").first
        expect(checkbox_span).to be_present
        expect(checkbox_span["class"]).to include("tui-checkbox--checked")
      end
    end
  end

  # -----------------------------------------------------------------------
  # Empty state
  # -----------------------------------------------------------------------
  describe "empty state" do
    it "renders no-notifications copy when empty + filter=all" do
      expect(rendered.text).to include("no notifications.")
    end

    it "renders no-unread copy when empty + filter=unread" do
      rendered = render_inline(described_class.new(
        notifications: notifications_relation,
        filter: "unread",
        unread_count: 0
      ))
      expect(rendered.text).to include("no unread notifications.")
    end
  end

  # -----------------------------------------------------------------------
  # Table structure with notifications present
  # -----------------------------------------------------------------------
  describe "with notifications" do
    let(:unread_notification) do
      build_notification(id: 10, kind: "video_published", title: "video live!", unread: true)
    end
    let(:read_notification) do
      build_notification(id: 11, kind: "game_release_today", title: "game out", unread: false)
    end
    let(:full_relation) do
      rel = [ unread_notification, read_notification ]
      allow(rel).to receive(:any?).and_return(true)
      rel
    end

    subject(:rendered) do
      render_inline(described_class.new(
        notifications: full_relation,
        filter: "all",
        unread_count: 1
      ))
    end

    it "renders a .nf-table" do
      expect(rendered.css("table.nf-table")).to be_present
    end

    it "renders a row for each notification" do
      rows = rendered.css("tbody tr.tui-table__row")
      expect(rows.length).to eq(2)
    end

    it "marks the unread row with nf-table__row--unread" do
      unread_row = rendered.css("tr#notification_10").first
      expect(unread_row["class"]).to include("nf-table__row--unread")
    end

    it "marks the read row with nf-table__row--read" do
      read_row = rendered.css("tr#notification_11").first
      expect(read_row["class"]).to include("nf-table__row--read")
    end

    it "renders the kind chip for video_published as nf-kind-chip--channel" do
      chip = rendered.css("tr#notification_10 .nf-kind-chip").first
      expect(chip["class"]).to include("nf-kind-chip--channel")
      expect(chip.text.strip).to eq("video")
    end

    it "renders the kind chip for game_release_today as nf-kind-chip--game" do
      chip = rendered.css("tr#notification_11 .nf-kind-chip").first
      expect(chip["class"]).to include("nf-kind-chip--game")
      expect(chip.text.strip).to eq("game")
    end

    it "renders the muted chip class on read rows" do
      chip = rendered.css("tr#notification_11 .nf-kind-chip").first
      expect(chip["class"]).to include("nf-kind-chip--muted")
    end

    it "does not add muted chip class to unread rows" do
      chip = rendered.css("tr#notification_10 .nf-kind-chip").first
      expect(chip["class"]).not_to include("nf-kind-chip--muted")
    end

    it "renders the notification title" do
      row = rendered.css("tr#notification_10").first
      expect(row.text).to include("video live!")
    end

    it "renders per-row tui-focusable keys" do
      rows = rendered.css("tbody tr[data-tui-focusable]")
      keys = rows.map { |r| r["data-tui-focusable"] }
      expect(keys).to include("row_10", "row_11")
    end

    it "emits the turbo-frame wrapper" do
      frame = rendered.css("turbo-frame##{Pito::NotificationsFeedPanelComponent::FRAME_ID}").first
      expect(frame).to be_present
    end
  end

  # -----------------------------------------------------------------------
  # Kind chip helpers
  # -----------------------------------------------------------------------
  describe "#kind_chip_variant" do
    let(:component) do
      described_class.new(
        notifications: notifications_relation,
        filter: "all",
        unread_count: 0
      )
    end

    it "maps video_published → :danger" do
      expect(component.kind_chip_variant("video_published")).to eq(:danger)
    end

    it "maps game_release_today → :nf_game" do
      expect(component.kind_chip_variant("game_release_today")).to eq(:nf_game)
    end

    it "maps sync_error → :nf_system" do
      expect(component.kind_chip_variant("sync_error")).to eq(:nf_system)
    end

    it "defaults unknown kinds to :nf_system" do
      expect(component.kind_chip_variant("unknown_kind")).to eq(:nf_system)
    end
  end

  # -----------------------------------------------------------------------
  # Bulk action forms present in the toolbar
  # -----------------------------------------------------------------------
  describe "bulk action toolbar" do
    it "renders a [read] submit button" do
      expect(rendered.text).to include("[read]")
    end

    it "renders an [un-read] submit button" do
      expect(rendered.text).to include("[un-read]")
    end
  end
end
