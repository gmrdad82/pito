require "rails_helper"

RSpec.describe "channels/_google_panel.html.erb", type: :view do
  it "renders the no-connection empty state with [connect this channel]" do
    channel = create(:channel) # no youtube_connection
    render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: nil }
    expect(rendered).to include("no Google connection on this channel")
    expect(rendered).to include("[connect this channel]")
  end

  # 2026-05-11 (later) — root pane class regression guard. The panel
  # sits beside the analytics pane on /channels/:slug row 2 inside a
  # shared `.pane-row`. It must use the plain `.pane` class so the
  # workspace zebra rule (`.pane:nth-child(even)` →
  # `--color-pane-bg-b`) paints it visually distinct from the
  # analytics pane on its left. `.pane--standalone` would suppress
  # that nth-child rule.
  it "uses the plain `.pane` class on its root (no `pane--standalone`)" do
    channel = create(:channel)
    render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: nil }
    root_classes = rendered[/<div class="([^"]*)"\s+data-google-panel/, 1]
    expect(root_classes).not_to be_nil
    expect(root_classes.split(/\s+/)).to include("pane")
    expect(root_classes).not_to include("pane--standalone")
  end

  # 2026-05-11 (height fix) — equal-height pane regression guard.
  # The /settings pane-rows render side-by-side panes at MATCHING
  # heights because flex stretches each item's margin-box to the
  # tallest sibling's height. When the Google pane carried an inline
  # `margin-bottom: 8px` on its `.pane` root, the analytics pane
  # (no such margin) and the Google pane had to share the same
  # margin-box height — so the Google pane's BORDER-BOX shrank by
  # 8px, leaving its background ending visibly above the analytics
  # bottom edge. The /settings layout sidesteps this by keeping
  # margin-bottom on the inner `<fieldset>` only; this pane follows
  # the same rule.
  it "does NOT set inline margin-bottom on its `.pane` root (breaks flex stretch)" do
    channel = create(:channel)
    render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: nil }
    root_open_tag = rendered[/<div class="pane"[^>]*data-google-panel[^>]*>/]
    expect(root_open_tag).not_to be_nil,
      "expected the Google panel root `<div class=\"pane\" data-google-panel ...>` to render"
    expect(root_open_tag).not_to match(/margin-bottom\s*:/i),
      "the Google pane root must not carry inline `margin-bottom` — it breaks side-by-side flex stretch with the analytics pane (asymmetric margins shrink the visible border-box). Move spacing to `.pane-row` margin-bottom (already 8px) or to an inner element."
  end

  context "with a connection" do
    let(:user) { User.first || create(:user) }
    let(:connection) do
      create(:youtube_connection,
             user: user,
             email: "alice@example.test",
             last_authorized_at: 3.hours.ago)
    end
    let(:channel) { create(:channel, youtube_connection: connection) }

    it "renders the Google heading" do
      render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: connection }
      expect(rendered).to match(/<h2[^>]*>Google<\/h2>/)
    end

    it "renders the last-authorized row" do
      render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: connection }
      expect(rendered).to include("last authorized")
      # `compact_time_ago(3.hours.ago)` returns a compact "~3h ago" form.
      expect(rendered).to match(/last authorized.*?h ago/m)
    end

    it "renders the healthy state row" do
      render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: connection }
      expect(rendered).to include("state")
      expect(rendered).to include("healthy")
    end

    it "does NOT render the 'connected as' row" do
      render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: connection }
      expect(rendered).not_to match(/connected as/i)
      # And no email leak either — the trimmed panel must not display
      # the connection email anywhere.
      expect(rendered).not_to include("alice@example.test")
    end

    it "does NOT render the 'scopes' row" do
      render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: connection }
      expect(rendered).not_to match(/scopes/i)
      expect(rendered).not_to include("youtube.readonly")
    end

    it "renders 'needs reauth' state when the connection is in needs_reauth" do
      connection.update!(needs_reauth: true)
      render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: connection }
      expect(rendered).to include("needs reauth")
      expect(rendered).to include("[reconnect]")
    end
  end
end
