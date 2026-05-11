require "rails_helper"

# Phase 24 — per-channel `[revoke]` flow. Two-action controller mirrors
# `DeletionsController` / `SyncsController` — GET renders the wide-modal
# confirmation page; POST consumes `confirm=yes` and enqueues
# `DeleteChannelDataJob`. Yes/no boundary on `confirm`.
RSpec.describe "ChannelRevokes", type: :request do
  before { ChannelSync.clear }

  let(:connection) { create(:youtube_connection) }
  let!(:channel) { create(:channel, youtube_connection: connection, title: "Hello World") }

  describe "GET /channels/:id/revoke" do
    it "returns 200 and renders the modal body with title + cascade counts" do
      get revoke_channel_path(channel)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Hello World")
      expect(response.body).to include("confirm revoke")
      # BracketedLinkComponent renders [<span class="bl">cancel</span>],
      # so the literal "[cancel]" is split across span boundaries.
      expect(response.body).to include('<span class="bl">cancel</span>')
    end

    it "renders the seven cascade categories (zeros for a bare channel)" do
      get revoke_channel_path(channel)
      expect(response.body).to include("video")
      expect(response.body).to include("analytics record")
      expect(response.body).to include("diff record")
      expect(response.body).to include("change-log record")
      expect(response.body).to include("link record")
      expect(response.body).to include("rejected-import record")
      expect(response.body).to include("calendar entry")
    end

    it "falls back to the UC-id slug when title is blank" do
      # 22-char slug after "UC" per Channel::CHANNEL_URL_REGEX.
      untitled = Channel.create!(
        channel_url: "https://www.youtube.com/channel/UCfallbackslug22charslug",
        title: nil
      )
      get revoke_channel_path(untitled)
      expect(response.body).to include("UCfallbackslug22charslug")
    end

    it "renders the last-channel hint when this is the only channel on the connection" do
      get revoke_channel_path(channel)
      expect(response.body).to include("last channel on the connection")
    end

    it "omits the last-channel hint when another channel shares the connection" do
      companion = create(:channel, youtube_connection: connection)
      get revoke_channel_path(channel)
      expect(response.body).not_to include("last channel on the connection")
      expect(companion).to be_persisted
    end

    it "omits the last-channel hint when the channel has no connection" do
      bare = create(:channel)
      get revoke_channel_path(bare)
      expect(response.body).not_to include("last channel on the connection")
    end

    it "returns 404 for a non-existent slug" do
      expect { get "/channels/UCnoneexistnoneexistnoey/revoke" }
        .not_to raise_error
      expect(response).to have_http_status(:not_found)
    end

    context "unauthenticated", :unauthenticated do
      it "redirects to /login" do
        get revoke_channel_path(channel)
        expect(response).to redirect_to(login_path)
      end
    end
  end

  describe "POST /channels/:id/revoke" do
    it "with confirm=yes enqueues DeleteChannelDataJob and redirects to /channels" do
      expect {
        post revoke_channel_path(channel), params: { confirm: "yes" }
      }.to change(DeleteChannelDataJob.jobs, :size).by(1)

      job = DeleteChannelDataJob.jobs.last
      expect(job["args"]).to eq([ channel.id, connection.id ])

      expect(response).to redirect_to(channels_path)
      expect(flash[:notice]).to include("channel revoke scheduled")
    end

    it "without confirm enqueues no job and redirects back to the channel show" do
      expect {
        post revoke_channel_path(channel)
      }.not_to change(DeleteChannelDataJob.jobs, :size)

      expect(response).to redirect_to(channel_path(channel))
      expect(flash[:alert]).to include("revoke cancelled")
    end

    it "with confirm=true (boundary violation) enqueues no job" do
      # The yes/no boundary rule: only "yes" is accepted.
      expect {
        post revoke_channel_path(channel), params: { confirm: "true" }
      }.not_to change(DeleteChannelDataJob.jobs, :size)
      expect(response).to redirect_to(channel_path(channel))
    end

    it "with confirm=1 enqueues no job (yes/no boundary strict)" do
      expect {
        post revoke_channel_path(channel), params: { confirm: "1" }
      }.not_to change(DeleteChannelDataJob.jobs, :size)
      expect(response).to redirect_to(channel_path(channel))
    end

    it "passes nil for the connection snapshot when the channel has no connection" do
      bare = create(:channel,
                    channel_url: "https://www.youtube.com/channel/UCsnapnilxxxxxxxxxxxxxxx")

      expect {
        post revoke_channel_path(bare), params: { confirm: "yes" }
      }.to change(DeleteChannelDataJob.jobs, :size).by(1)

      job = DeleteChannelDataJob.jobs.last
      expect(job["args"]).to eq([ bare.id, nil ])
    end

    context "unauthenticated", :unauthenticated do
      it "redirects to /login and enqueues no job" do
        expect {
          post revoke_channel_path(channel), params: { confirm: "yes" }
        }.not_to change(DeleteChannelDataJob.jobs, :size)

        expect(response).to redirect_to(login_path)
      end
    end
  end
end
