require "rails_helper"

RSpec.describe "Channels::BulkRevokes", type: :request do
  before { ChannelSync.clear }

  let(:connection) { create(:youtube_connection) }
  let!(:channel_a) { create(:channel, youtube_connection: connection, title: "Alpha") }
  let!(:channel_b) { create(:channel, youtube_connection: connection, title: "Bravo") }
  let!(:channel_c) { create(:channel, youtube_connection: connection, title: "Charlie") }

  describe "GET /channels/revokes/:ids" do
    it "renders modal with three channels listed, aggregated counts" do
      get channels_bulk_revoke_path(ids: [ channel_a.id, channel_b.id, channel_c.id ].join(","))
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alpha")
      expect(response.body).to include("Bravo")
      expect(response.body).to include("Charlie")
      expect(response.body).to include("revoke 3 channels")
      expect(response.body).to include("confirm revoke")
    end

    it "lists the connection emails that will be orphaned" do
      # All three channels are the only members of `connection`, so the
      # connection will be orphaned by this bulk revoke.
      get channels_bulk_revoke_path(ids: [ channel_a.id, channel_b.id, channel_c.id ].join(","))
      expect(response.body).to include(connection.email)
    end

    it "renders in single-channel mode when called with one id (bulk-as-foundation)" do
      get channels_bulk_revoke_path(ids: channel_a.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alpha")
      expect(response.body).to include("revoke 1 channel")
    end

    it "redirects to /channels with `nothing to revoke` when no channels match" do
      get channels_bulk_revoke_path(ids: "9999")
      expect(response).to redirect_to(channels_path)
      expect(flash[:alert]).to include("nothing to revoke")
    end

    context "with > 10 channels" do
      let(:many_connection) { create(:youtube_connection) }
      let!(:many_channels) do
        Array.new(12) do |i|
          create(:channel,
                 title: "Channel #{i}",
                 youtube_connection: many_connection,
                 channel_url: "https://www.youtube.com/channel/UC#{('z' * 22)[0, 20]}#{i.to_s.rjust(2, '0')}")
        end
      end

      it "caps the preview list at 10 with an `…and 2 more` suffix" do
        get channels_bulk_revoke_path(ids: many_channels.map(&:id).join(","))
        expect(response.body).to include("…and 2 more")
      end
    end
  end

  describe "POST /channels/revokes/:ids" do
    it "with confirm=yes enqueues one DeleteChannelDataJob per channel and redirects" do
      ids = [ channel_a.id, channel_b.id, channel_c.id ]
      expect {
        post channels_bulk_revoke_path(ids: ids.join(",")), params: { confirm: "yes" }
      }.to change(DeleteChannelDataJob.jobs, :size).by(3)

      enqueued = DeleteChannelDataJob.jobs.last(3)
      enqueued_args = enqueued.map { |j| j["args"] }
      expect(enqueued_args).to contain_exactly(
        [ channel_a.id, connection.id ],
        [ channel_b.id, connection.id ],
        [ channel_c.id, connection.id ]
      )

      expect(response).to redirect_to(channels_path)
      expect(flash[:notice]).to include("3 channel revokes scheduled")
    end

    it "without confirm enqueues nothing" do
      expect {
        post channels_bulk_revoke_path(ids: channel_a.id)
      }.not_to change(DeleteChannelDataJob.jobs, :size)
      expect(response).to redirect_to(channels_path)
      expect(flash[:alert]).to include("revoke cancelled")
    end

    it "redirects with `nothing to revoke` when the id list matches nothing" do
      post channels_bulk_revoke_path(ids: "9999"), params: { confirm: "yes" }
      expect(response).to redirect_to(channels_path)
      expect(flash[:alert]).to include("nothing to revoke")
    end

    it "pluralizes the notice correctly for a single channel" do
      post channels_bulk_revoke_path(ids: channel_a.id), params: { confirm: "yes" }
      expect(flash[:notice]).to include("1 channel revoke scheduled")
      expect(flash[:notice]).not_to include("revokes scheduled")
    end

    context "unauthenticated", :unauthenticated do
      it "redirects to login and enqueues no jobs" do
        expect {
          post channels_bulk_revoke_path(ids: channel_a.id), params: { confirm: "yes" }
        }.not_to change(DeleteChannelDataJob.jobs, :size)
        expect(response).to redirect_to(login_path)
      end
    end
  end
end
