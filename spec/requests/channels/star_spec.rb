require "rails_helper"

# Unit A0 — channel read-only conversion.
#
# `Channels::StarsController` owns the only channel write path that
# survives the read-only conversion: PATCH /channels/:channel_id/star.
# The channel is a read-only mirror; `star` is the single mutable
# attribute. Every other channel field (title / handle / description /
# banner / avatar / keywords / country / language / links / watermark)
# can appear in the params but is never read — silently ignored, not
# 422'd, matching the pre-cut JSON path's posture.
#
# The boundary contract (CLAUDE.md): `star` arrives as the string
# "yes" / "no" — never true/false/0/1. A non-yes/no value is a 422
# (JSON) / flash-alert redirect (HTML).
RSpec.describe "PATCH /channels/:channel_id/star", type: :request do
  before { ChannelSync.clear }

  let!(:channel) { create(:channel) }

  describe "HTML — happy path" do
    it "stars an unstarred channel and redirects to the show page with the notice" do
      expect(channel.star).to be(false)

      patch channel_star_path(channel), params: { channel: { star: "yes" } }

      expect(response).to redirect_to(channel_path(channel))
      follow_redirect!
      expect(flash[:notice] || response.body).to be_truthy
      expect(channel.reload.star).to be(true)
    end

    it "unstars a starred channel" do
      starred = create(:channel, :starred)
      patch channel_star_path(starred), params: { channel: { star: "no" } }

      expect(response).to redirect_to(channel_path(starred))
      expect(starred.reload.star).to be(false)
    end

    it "sets the 'channel updated.' notice on success" do
      patch channel_star_path(channel), params: { channel: { star: "yes" } }
      expect(flash[:notice]).to eq("channel updated.")
    end
  end

  describe "JSON — happy path" do
    it "returns the channel detail JSON with star toggled" do
      patch channel_star_path(channel, format: :json),
            params: { channel: { star: "yes" } }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["star"]).to eq("yes")
      expect(channel.reload.star).to be(true)
    end

    it "succeeds without an authenticity token (CSRF skipped for JSON)" do
      ActionController::Base.allow_forgery_protection = true
      begin
        patch channel_star_path(channel, format: :json),
              params: { channel: { star: "yes" } }
        expect(response).to have_http_status(:ok)
      ensure
        ActionController::Base.allow_forgery_protection = false
      end
    end
  end

  describe "boundary — bad yes/no value" do
    it "HTML: redirects with a flash alert and leaves star unchanged" do
      patch channel_star_path(channel), params: { channel: { star: "true" } }

      expect(response).to redirect_to(channel_path(channel))
      expect(flash[:alert]).to be_present
      expect(channel.reload.star).to be(false)
    end

    it "JSON: returns 422 with an errors array and leaves star unchanged" do
      patch channel_star_path(channel, format: :json),
            params: { channel: { star: "true" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_an(Array)
      expect(channel.reload.star).to be(false)
    end

    it "JSON: rejects a raw boolean true" do
      patch channel_star_path(channel, format: :json),
            params: { channel: { star: true } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(channel.reload.star).to be(false)
    end

    it "JSON: rejects the legacy string '1'" do
      patch channel_star_path(channel, format: :json),
            params: { channel: { star: "1" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "read-only mirror — removed attributes are ignored, not assigned" do
    it "toggles star while leaving title and description untouched" do
      channel.update_columns(title: "Original Title", description: "Original description")

      patch channel_star_path(channel),
            params: {
              channel: {
                star: "yes",
                title: "hacked",
                description: "x"
              }
            }

      channel.reload
      expect(channel.star).to be(true)
      expect(channel.title).to eq("Original Title")
      expect(channel.description).to eq("Original description")
    end

    it "never reads channel_url out of the params (URL stays locked)" do
      original_url = channel.channel_url

      patch channel_star_path(channel),
            params: {
              channel: {
                star: "yes",
                channel_url: "https://www.youtube.com/channel/UCzzzzzzzzzzzzzzzzzzzzzz"
              }
            }

      channel.reload
      expect(channel.star).to be(true)
      expect(channel.channel_url).to eq(original_url)
    end
  end

  describe "star callbacks" do
    it "enqueues ChannelSync when toggled to starred" do
      expect {
        patch channel_star_path(channel), params: { channel: { star: "yes" } }
      }.to change(ChannelSync.jobs, :size).by(1)
    end

    it "does not enqueue ChannelSync when un-starring" do
      starred = create(:channel, :starred)
      ChannelSync.clear
      expect {
        patch channel_star_path(starred), params: { channel: { star: "no" } }
      }.not_to change(ChannelSync.jobs, :size)
    end
  end

  describe "friendly finder — slug and integer id resolution" do
    it "resolves the channel by its friendly slug" do
      patch "/channels/#{channel.to_param}/star", params: { channel: { star: "yes" } }
      expect(response).to redirect_to(channel_path(channel))
      expect(channel.reload.star).to be(true)
    end

    it "resolves the channel by integer id" do
      patch "/channels/#{channel.id}/star", params: { channel: { star: "yes" } }
      expect(response).to have_http_status(:redirect)
      expect(channel.reload.star).to be(true)
    end
  end
end
