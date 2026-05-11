require "rails_helper"

# Phase 7.5 §11c — PATCH /channels/:id HTML form path.
#
# The pre-11c JSON `star`-toggle contract is covered in
# `spec/requests/channels_spec.rb` and stays intact. This spec
# covers the HTML form flow: dispatch through Youtube::Client,
# the local-only-update branch, the 14-day gate defense-in-depth,
# and every controller-level sad path (NeedsReauthError, quota,
# 5xx transient, validation, watermark).
RSpec.describe "PATCH /channels/:id (edit form)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:connection) { create(:youtube_connection) }
  let!(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcabcabcabcabcabcabcA",
           title: "Pre-existing title",
           description: "Pre-existing description",
           country: "US",
           default_language: "en",
           youtube_connection: connection)
  end
  let(:unlinked_channel) { create(:channel, youtube_connection: nil) }

  before do
    ChannelSync.clear
    # Stub the whole client so we don't try to talk to YouTube.
    allow(Youtube::Client).to receive(:new).and_return(youtube_client)
  end

  let(:youtube_client) do
    instance_double(
      Youtube::Client,
      update_channel: { title: "New title", description: "New description" },
      set_watermark: { ok: true },
      unset_watermark: { ok: true }
    )
  end

  describe "GET /channels/:id/edit" do
    it "returns 200 and renders the edit form" do
      get edit_channel_path(channel)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("edit channel")
      expect(response.body).to include('name="channel[title]"')
      expect(response.body).to include('name="channel[description]"')
      expect(response.body).to include('name="channel[country]"')
      expect(response.body).to include('name="channel[default_language]"')
      expect(response.body).to include('name="channel[keywords]"')
    end

    it "renders the locked-url notice" do
      get edit_channel_path(channel)
      expect(response.body).to include("URL is locked after creation.")
      expect(response.body).to include(channel.channel_url)
    end

    it "renders the local-only banner when channel has no youtube_connection" do
      get edit_channel_path(unlinked_channel)
      expect(response.body).to include("this channel is not connected to a google identity")
    end

    it "does not render the local-only banner when channel is connected" do
      get edit_channel_path(channel)
      expect(response.body).not_to include("this channel is not connected to a google identity")
    end

    it "hides the title input and renders the [remind me] link when the gate is open" do
      channel.update_columns(title: "Locked title", title_changed_at: 3.days.ago)
      get edit_channel_path(channel)
      expect(response.body).not_to include('name="channel[title]"')
      expect(response.body).to match(/title was changed on \d{4}-\d{2}-\d{2}/)
      expect(response.body).to include("[remind me on")
      expect(response.body).to include('data-controller="reminder-link"')
    end

    it "shows the title input when the 14-day window has expired" do
      channel.update_columns(title_changed_at: 20.days.ago)
      get edit_channel_path(channel)
      expect(response.body).to include('name="channel[title]"')
      expect(response.body).not_to match(/title was changed on/)
    end

    it "hides the handle input and renders [remind me] when the handle gate is open" do
      channel.update_columns(handle: "@x", handle_changed_at: 1.day.ago)
      get edit_channel_path(channel)
      expect(response.body).not_to include('name="channel[handle]"')
      expect(response.body).to match(/handle was changed on \d{4}-\d{2}-\d{2}/)
      expect(response.body).to include("[remind me on")
    end
  end

  describe "PATCH /channels/:id (happy path)" do
    it "single dirty field — only description goes through update_channel" do
      patch channel_path(channel),
            params: { channel: { description: "New description only" } }

      expect(youtube_client).to have_received(:update_channel) do |_chan, field_set|
        expect(field_set.keys).to contain_exactly(:description)
      end
      expect(response).to redirect_to(channel_path(channel))
      expect(flash[:notice]).to eq("channel updated.")
      expect(channel.reload.description).to eq("New description only")
    end

    it "multi-field dirty subset (title + description + country)" do
      patch channel_path(channel),
            params: { channel: { title: "New title", description: "New desc", country: "DE" } }

      expect(youtube_client).to have_received(:update_channel) do |_chan, field_set|
        expect(field_set).to include(:title, :description, :country)
      end
      expect(response).to redirect_to(channel_path(channel))
    end

    it "stamps title_changed_at when title changes" do
      travel_to(Time.current) do
        patch channel_path(channel), params: { channel: { title: "Brand new title" } }
        expect(channel.reload.title_changed_at).to be_within(1.second).of(Time.current)
      end
    end

    it "does NOT stamp title_changed_at when title is unchanged" do
      channel.update_columns(title_changed_at: nil)
      patch channel_path(channel),
            params: { channel: { title: channel.title, description: "Description only" } }
      expect(channel.reload.title_changed_at).to be_nil
    end

    it "stamps handle_changed_at when handle changes" do
      travel_to(Time.current) do
        patch channel_path(channel), params: { channel: { handle: "@brandnew" } }
        expect(channel.reload.handle_changed_at).to be_within(1.second).of(Time.current)
      end
    end

    it "short-circuits to redirect with 'no changes to save' when params[:channel] is empty" do
      patch channel_path(channel), params: { channel: {} }
      expect(youtube_client).not_to have_received(:update_channel)
      expect(response).to redirect_to(channel_path(channel))
      expect(flash[:notice]).to eq("no changes to save.")
    end

    it "short-circuits when params are absent entirely" do
      patch channel_path(channel)
      expect(response).to redirect_to(channel_path(channel))
      expect(flash[:notice]).to eq("no changes to save.")
    end
  end

  describe "PATCH /channels/:id (local-only — no youtube_connection)" do
    it "writes locally and skips Youtube::Client entirely" do
      patch channel_path(unlinked_channel),
            params: { channel: { description: "Local only desc" } }

      expect(Youtube::Client).not_to have_received(:new)
      expect(unlinked_channel.reload.description).to eq("Local only desc")
      expect(response).to redirect_to(channel_path(unlinked_channel))
      expect(flash[:notice]).to include("connect a google identity")
    end
  end

  describe "PATCH /channels/:id (watermark-only flows)" do
    let(:fixture_io) do
      Rack::Test::UploadedFile.new(
        StringIO.new("fake_png_bytes"),
        "image/png",
        original_filename: "watermark.png"
      )
    end

    it "uploads a new watermark; update_channel NOT called when no other fields are dirty" do
      patch channel_path(channel),
            params: {
              channel: {
                watermark: fixture_io,
                watermark_timing: "always"
              }
            }

      expect(youtube_client).to have_received(:set_watermark)
      expect(youtube_client).not_to have_received(:update_channel)
      expect(response).to redirect_to(channel_path(channel))
    end

    it "removes a watermark when watermark_remove=yes" do
      patch channel_path(channel),
            params: { channel: { watermark_remove: "yes" } }

      expect(youtube_client).to have_received(:unset_watermark)
      expect(youtube_client).not_to have_received(:update_channel)
      channel.reload
      expect(channel.watermark_url).to be_nil
      expect(channel.watermark_timing).to be_nil
      expect(channel.watermark_offset_ms).to be_nil
    end
  end

  describe "PATCH /channels/:id (sad paths)" do
    it "NeedsReauthError flags the connection and redirects to /settings/youtube" do
      allow(youtube_client).to receive(:update_channel).and_raise(Youtube::NeedsReauthError, "bad")
      patch channel_path(channel), params: { channel: { description: "x" } }
      expect(connection.reload.needs_reauth?).to be(true)
      expect(response).to redirect_to(settings_youtube_path)
      expect(flash[:alert]).to include("needs re-authorization")
    end

    it "QuotaExhaustedError re-renders the edit form with flash, no DB mutation" do
      original_desc = channel.description
      allow(youtube_client).to receive(:update_channel).and_raise(Youtube::QuotaExhaustedError, "boom")
      patch channel_path(channel), params: { channel: { description: "new desc" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("youtube api quota exhausted")
      expect(channel.reload.description).to eq(original_desc)
    end

    it "TransientError re-renders the edit form with friendly flash" do
      allow(youtube_client).to receive(:update_channel).and_raise(Youtube::TransientError, "5xx")
      patch channel_path(channel), params: { channel: { description: "x" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("youtube is having trouble")
    end

    it "PermanentError re-renders the edit form with the surfaced reason" do
      allow(youtube_client).to receive(:update_channel).and_raise(Youtube::PermanentError, "bad request: title too long")
      patch channel_path(channel), params: { channel: { description: "x" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("youtube refused the update")
    end

    it "country format reject re-renders :edit with the validation error" do
      patch channel_path(channel), params: { channel: { country: "usa" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Country")
    end

    it "default_language format reject re-renders :edit" do
      patch channel_path(channel), params: { channel: { default_language: "ENGLISH" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Default language")
    end

    it "watermark_offset_ms negative re-renders :edit" do
      patch channel_path(channel),
            params: { channel: { watermark_offset_ms: -50 } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Watermark offset ms")
    end

    it "links 6th entry rejected by Channel#links_shape validator" do
      links = 6.times.map do |i|
        { "title" => "L#{i}", "url" => "https://example#{i}.test" }
      end
      patch channel_path(channel),
            params: { channel: { links_attributes: links.each_with_index.to_h { |h, i| [ i.to_s, h ] } } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("at most 5")
    end

    it "links with blank url rejected by validator" do
      patch channel_path(channel),
            params: {
              channel: {
                links_attributes: {
                  "0" => { "title" => "Has title", "url" => "" }
                }
              }
            }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("url must be a valid http(s) URL")
    end
  end

  describe "14-day gate defense-in-depth" do
    it "strips the title from field_set when client gate is open and surfaces a notice" do
      channel.update_columns(title_changed_at: 3.days.ago)
      patch channel_path(channel),
            params: { channel: { title: "Bypass attempt", description: "Desc edit" } }

      expect(youtube_client).to have_received(:update_channel) do |_chan, field_set|
        expect(field_set).not_to include(:title)
        expect(field_set).to include(:description)
      end
      expect(response).to redirect_to(channel_path(channel))
      expect(flash[:notice]).to include("title is locked until")
    end

    it "strips both title AND handle when both gates are open" do
      channel.update_columns(title_changed_at: 3.days.ago, handle_changed_at: 5.days.ago)
      patch channel_path(channel),
            params: { channel: { title: "Nope", handle: "@nope", description: "Desc" } }
      expect(youtube_client).to have_received(:update_channel) do |_chan, field_set|
        expect(field_set).not_to include(:title)
        expect(field_set).not_to include(:handle)
        expect(field_set).to include(:description)
      end
    end

    it "short-circuits to 'no changes' when ALL submitted fields are gate-stripped" do
      channel.update_columns(title_changed_at: 3.days.ago)
      patch channel_path(channel), params: { channel: { title: "Nope" } }
      # title got stripped; nothing left to update. Controller still
      # warns about the gate via flash[:notice].
      expect(youtube_client).not_to have_received(:update_channel)
      expect(response).to redirect_to(channel_path(channel))
    end
  end

  describe "JSON path stays untouched (regression guard)" do
    it "PATCH .json with star=yes still works through the legacy yes/no path" do
      patch channel_path(channel, format: :json), params: { channel: { star: "yes" } }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["star"]).to eq("yes")
    end

    it "PATCH .json with star=true is still rejected with 422" do
      patch channel_path(channel, format: :json), params: { channel: { star: true } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
