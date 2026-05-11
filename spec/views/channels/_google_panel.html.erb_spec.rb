require "rails_helper"

RSpec.describe "channels/_google_panel.html.erb", type: :view do
  it "renders the no-connection empty state with [connect this channel]" do
    channel = create(:channel) # no youtube_connection
    render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: nil }
    expect(rendered).to include("no Google connection on this channel")
    expect(rendered).to include("[connect this channel]")
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

    it "renders the Google connection heading" do
      render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: connection }
      expect(rendered).to include("Google connection")
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
