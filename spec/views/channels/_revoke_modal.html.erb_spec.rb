require "rails_helper"

RSpec.describe "channels/_revoke_modal.html.erb", type: :view do
  let(:counts) do
    ChannelRevokeCounts::Counts.new(
      videos: 5, analytics: 100, diffs: 2, change_logs: 7,
      links: 3, rejected_imports: 1, calendar_entries: 6
    )
  end

  describe "single-channel mode" do
    let(:connection) { create(:youtube_connection, email: "alice@example.test") }
    let(:channel) { create(:channel, youtube_connection: connection, title: "My Channel") }

    it "renders the channel title in the H1" do
      render partial: "channels/revoke_modal", locals: {
        channel: channel, counts: counts, is_last_channel_on_connection: false,
        form_url: "/channels/#{channel.to_param}/revoke",
        cancel_url: "/channels/#{channel.to_param}"
      }
      expect(rendered).to include('revoke channel "My Channel"?')
    end

    it "renders the seven cascade counts with their numeric values" do
      render partial: "channels/revoke_modal", locals: {
        channel: channel, counts: counts, is_last_channel_on_connection: false,
        form_url: "x", cancel_url: "y"
      }
      expect(rendered).to include("5 videos")
      expect(rendered).to include("100 analytics records")
      expect(rendered).to include("2 diff records")
      expect(rendered).to include("7 change-log records")
      expect(rendered).to include("3 link records")
      expect(rendered).to include("1 rejected-import record")
      expect(rendered).to include("6 calendar entry (entries)")
    end

    it "uses singular pluralization when count is 1" do
      single = ChannelRevokeCounts::Counts.new(
        videos: 1, analytics: 1, diffs: 1, change_logs: 1,
        links: 1, rejected_imports: 1, calendar_entries: 1
      )
      render partial: "channels/revoke_modal", locals: {
        channel: channel, counts: single, is_last_channel_on_connection: false,
        form_url: "x", cancel_url: "y"
      }
      expect(rendered).to include("1 video<br>")
      expect(rendered).to include("1 analytics record<br>")
      expect(rendered).to include("1 calendar entry.")
      expect(rendered).not_to include("1 videos")
      expect(rendered).not_to include("1 analytics records")
    end

    it "renders the last-channel hint with the connection email when applicable" do
      render partial: "channels/revoke_modal", locals: {
        channel: channel, counts: counts, is_last_channel_on_connection: true,
        form_url: "x", cancel_url: "y"
      }
      expect(rendered).to include("alice@example.test")
      expect(rendered).to include("last channel on the connection")
    end

    it "omits the last-channel hint when false" do
      render partial: "channels/revoke_modal", locals: {
        channel: channel, counts: counts, is_last_channel_on_connection: false,
        form_url: "x", cancel_url: "y"
      }
      expect(rendered).not_to include("last channel on the connection")
    end

    it "renders [cancel] targeting the cancel_url" do
      render partial: "channels/revoke_modal", locals: {
        channel: channel, counts: counts, is_last_channel_on_connection: false,
        form_url: "/post-here", cancel_url: "/cancel-here"
      }
      expect(rendered).to include("/cancel-here")
      expect(rendered).to include("[<span class=\"bl\">cancel</span>]")
    end

    it "renders the [confirm revoke] button with confirm=yes hidden field" do
      render partial: "channels/revoke_modal", locals: {
        channel: channel, counts: counts, is_last_channel_on_connection: false,
        form_url: "/post-here", cancel_url: "/cancel-here"
      }
      expect(rendered).to include('<input type="hidden" name="confirm" value="yes">')
      expect(rendered).to include("confirm revoke")
      expect(rendered).to match(/<form[^>]*action="\/post-here"/)
    end

    it "does NOT use data-turbo-confirm or any JS confirm dialog" do
      render partial: "channels/revoke_modal", locals: {
        channel: channel, counts: counts, is_last_channel_on_connection: false,
        form_url: "x", cancel_url: "y"
      }
      expect(rendered).not_to include("data-turbo-confirm")
      expect(rendered).not_to include("confirm()")
    end

    it "falls back to the UC-id slug when the channel title is blank" do
      blank = create(:channel,
                     title: nil,
                     channel_url: "https://www.youtube.com/channel/UCblankslugfallbackxxxxx")
      render partial: "channels/revoke_modal", locals: {
        channel: blank, counts: counts, is_last_channel_on_connection: false,
        form_url: "x", cancel_url: "y"
      }
      expect(rendered).to include("UCblankslugfallbackxxxxx")
    end
  end

  describe "bulk-channel mode" do
    let(:connection) { create(:youtube_connection, email: "alice@example.test") }
    let(:channel_a) { create(:channel, title: "Alpha", youtube_connection: connection) }
    let(:channel_b) { create(:channel, title: "Bravo", youtube_connection: connection) }

    it "renders 'revoke N channels' in the H1 and lists each channel" do
      render partial: "channels/revoke_modal", locals: {
        channels: [ channel_a, channel_b ], overflow_count: 0,
        counts: counts, orphan_connections: [],
        form_url: "x", cancel_url: "y"
      }
      expect(rendered).to include("revoke 2 channels")
      expect(rendered).to include("Alpha")
      expect(rendered).to include("Bravo")
    end

    it "renders an `…and N more` suffix when overflow_count > 0" do
      render partial: "channels/revoke_modal", locals: {
        channels: [ channel_a ], overflow_count: 3,
        counts: counts, orphan_connections: [],
        form_url: "x", cancel_url: "y"
      }
      expect(rendered).to include("revoke 4 channels")
      expect(rendered).to include("…and 3 more")
    end

    it "lists the email of every connection that will be orphaned" do
      render partial: "channels/revoke_modal", locals: {
        channels: [ channel_a, channel_b ], overflow_count: 0,
        counts: counts, orphan_connections: [ connection ],
        form_url: "x", cancel_url: "y"
      }
      expect(rendered).to include("alice@example.test")
      expect(rendered).to include("Google OAuth grant")
    end

    it "renders no orphan-connection block when none would be orphaned" do
      render partial: "channels/revoke_modal", locals: {
        channels: [ channel_a ], overflow_count: 0,
        counts: counts, orphan_connections: [],
        form_url: "x", cancel_url: "y"
      }
      expect(rendered).not_to include("Google OAuth grant")
    end
  end
end
