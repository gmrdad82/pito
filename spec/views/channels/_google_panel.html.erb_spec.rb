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

    it "renders the connected-as email, scopes, last-authorized, and healthy state" do
      render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: connection }
      expect(rendered).to include("alice@example.test")
      expect(rendered).to include("youtube.readonly")
      expect(rendered).to include("healthy")
    end

    it "renders 'needs reauth' state when the connection is in needs_reauth" do
      connection.update!(needs_reauth: true)
      render partial: "channels/google_panel", locals: { channel: channel, youtube_connection: connection }
      expect(rendered).to include("needs reauth")
      expect(rendered).to include("[reconnect]")
    end
  end
end
