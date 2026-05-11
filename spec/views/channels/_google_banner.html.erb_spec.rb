require "rails_helper"

RSpec.describe "channels/_google_banner.html.erb", type: :view do
  it "renders empty state + [connect google] when no connections exist" do
    render partial: "channels/google_banner", locals: { youtube_connections: [] }
    expect(rendered).to include("no Google account connected")
    expect(rendered).to include("[connect google]")
  end

  it "posts the empty-state [connect google] button to /channels/connect_google" do
    render partial: "channels/google_banner", locals: { youtube_connections: [] }
    expect(rendered).to match(
      %r{<form[^>]*action="#{Regexp.escape(connect_google_channels_path)}"[^>]*method="post"}
    )
  end

  context "with one connection" do
    let(:user) { User.first || create(:user) }
    let(:connection) do
      create(:youtube_connection,
             user: user,
             email: "alice@example.test",
             last_authorized_at: 2.hours.ago)
    end

    it "renders the connection email + channel count + last-authorized + [+ add another Google account]" do
      render partial: "channels/google_banner", locals: { youtube_connections: [ connection ] }
      expect(rendered).to include("alice@example.test")
      expect(rendered).to include("0 channels")
      expect(rendered).to include("[+ add another Google account]")
    end

    it "wires the [+ add another Google account] button with account=new (prompt=select_account on the OAuth side)" do
      render partial: "channels/google_banner", locals: { youtube_connections: [ connection ] }
      expect(rendered).to include('<input type="hidden" name="account" value="new">')
    end

    it "renders 'N channels' singular when exactly one channel exists" do
      Channel.create!(channel_url: "https://www.youtube.com/channel/UC123456789012345678abcd",
                      youtube_connection_id: connection.id)
      render partial: "channels/google_banner", locals: { youtube_connections: [ connection ] }
      # "1 channel" with no trailing 's'; surrounding em-dash separator.
      expect(rendered).to match(/\b1 channel\b(?!s)/)
    end

    it "renders the needs-reauth banner above the list when the connection needs reauth" do
      connection.update!(needs_reauth: true)
      render partial: "channels/google_banner", locals: { youtube_connections: [ connection ] }
      expect(rendered).to include("[reconnect]")
    end
  end

  context "with multiple connections" do
    let(:user) { User.first || create(:user) }
    let!(:conn_a) do
      create(:youtube_connection, user: user, email: "a@example.test",
             last_authorized_at: 1.day.ago)
    end
    let!(:conn_b) do
      create(:youtube_connection, user: user, email: "b@example.test",
             last_authorized_at: 1.hour.ago)
    end

    it "renders one row per connection" do
      render partial: "channels/google_banner", locals: { youtube_connections: [ conn_b, conn_a ] }
      expect(rendered).to include("a@example.test")
      expect(rendered).to include("b@example.test")
    end
  end
end
