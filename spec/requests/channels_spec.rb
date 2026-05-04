require "rails_helper"

RSpec.describe "Channels", type: :request do
  let(:valid_url) { "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ" }
  let(:other_valid_url) { "https://www.youtube.com/channel/UCAAAAAAAAAAAAAAAAAAAAAA" }

  before { ChannelSync.clear }

  describe "GET /channels (index)" do
    it "returns 200" do
      get channels_path
      expect(response).to have_http_status(:ok)
    end

    it "shows empty state when no channels" do
      get channels_path
      expect(response.body).to include("no channels yet")
    end

    it "includes bulk toggle link" do
      get channels_path
      expect(response.body).to include("bulk")
    end

    context "with channels" do
      let!(:channel) { create(:channel) }

      it "displays the channel url" do
        get channels_path
        expect(response.body).to include(channel.channel_url)
      end

      it "renders the YouTube column header (formerly view)" do
        get channels_path
        expect(response.body).to include(">YouTube<")
      end

      it "does not render an OAuth column header" do
        get channels_path
        expect(response.body).not_to match(/<th[^>]*>\s*OAuth\s*</)
      end

      it "does not render a separate syncing column header" do
        get channels_path
        # last sync remains, syncing-as-its-own-header is gone
        expect(response.body).not_to match(/<th[^>]*>\s*syncing\s*</)
      end

      it "displays 5 data columns (open, url, YouTube, starred, last sync) plus action col" do
        get channels_path
        # Count <th> elements between <thead><tr> and </tr>. Strip bulk col
        # since it's hidden by default. The visible header tr contains:
        # action col + url + YouTube + starred + last sync = 5 visible <th>
        # plus 1 hidden bulk-select header (still present in DOM).
        thead = response.body.match(/<thead>(.*?)<\/thead>/m)[1]
        # 6 total <th> (1 hidden bulk col + 5 visible)
        expect(thead.scan(/<th\b/).size).to eq(6)
      end

      it "renders a sortable starred column header (lowercase, no star icon)" do
        get channels_path
        thead = response.body.match(/<thead>(.*?)<\/thead>/m)[1]
        expect(thead).to match(/<th class="sortable num" data-action="click->sortable-table#sort" data-sort-type="string">starred<\/th>/)
        expect(thead).not_to include("★")
      end

      it "renders starred cells as yes/no text (no star icon)" do
        starred = create(:channel, :starred)
        plain = create(:channel)
        get channels_path
        # Locate each row's starred cell. The starred column is the 4th
        # numeric cell (after url, YouTube, then starred). We assert the
        # response includes the literal "yes" / "no" strings rendered as
        # the starred cell value, and contains no star glyph.
        expect(response.body).not_to include("★")
        expect(response.body).to match(/<td class="num">yes<\/td>/)
        expect(response.body).to match(/<td class="num">no<\/td>/)
        expect(response.body).to include(starred.channel_url)
        expect(response.body).to include(plain.channel_url)
      end

      it "renders bracketed-checkbox filter chips (not bracketed link chips)" do
        get channels_path
        expect(response.body).to include("md-check-static")
        # ensure no checkmark prefix from the old chip style
        expect(response.body).not_to include("✓ starred")
      end

      it "renders the max-panes split-view subtext hidden by default (shown only when count exceeds max)" do
        get channels_path
        expect(response.body).to include("can be opened in split view")
        # The subtext is wrapped in a bulk-select target so JS can show/hide
        # it based on selection count vs max-panes. It must start hidden.
        expect(response.body).to match(/data-bulk-select-target="overMaxHint"\s+hidden/)
      end

      it "sources max-panes from AppSetting (not hardcoded)" do
        AppSetting.set("max_panes", "7")
        get channels_path
        expect(response.body).to include('data-bulk-select-max-panes-value="7"')
        expect(response.body).to include("max 7 channels at a time can be opened in split view")
      end

      it "open link points to show page" do
        get channels_path
        expect(response.body).to include("/channels/#{channel.id}")
      end

      it "renders the [view] external link with target=_blank" do
        get channels_path
        expect(response.body).to include(">view<")
        expect(response.body).to include('target="_blank"')
      end

      it "renders bulk select controls" do
        get channels_path
        expect(response.body).to include('data-bulk-select-target="checkbox"')
        expect(response.body).to include('data-bulk-select-max-panes-value="3"')
      end

      # Phase B — leading-separator pattern. Each `.action` span carries
      # its own `.action-sep` dot; the JS controller hides the dot on
      # whichever action is first-visible, so the toolbar never starts
      # with a dangling `· [ cancel ]`.
      it "renders the bulk-toolbar leading-separator pattern" do
        get channels_path
        expect(response.body).to include("bulk-toolbar")
        expect(response.body).to match(/<span class="action-sep" hidden>/)
      end

      it "ships with every leading separator hidden in the static initial render" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        actions = html.css('[data-bulk-select-target="actions"]').first
        expect(actions).not_to be_nil, "expected the bulk-select actions container in markup"
        separators = actions.css(".action-sep")
        expect(separators).not_to be_empty, "expected at least one .action-sep dot inside the toolbar"
        separators.each do |sep|
          expect(sep["hidden"]).not_to be_nil,
            "expected .action-sep to ship with the `hidden` attribute, got: #{sep.to_html}"
        end
      end
    end

    context "filters" do
      let!(:starred)   { create(:channel, :starred) }
      let!(:connected) { create(:channel, :connected) }
      let!(:plain)     { create(:channel) }

      it "filters by star=yes" do
        get channels_path, params: { star: "yes" }
        expect(response.body).to include(starred.channel_url)
        expect(response.body).not_to include(plain.channel_url)
      end

      it "does NOT filter when star=1 (yes/no convention is strict)" do
        get channels_path, params: { star: "1" }
        # star=1 is no longer a truthy filter — all channels render
        expect(response.body).to include(starred.channel_url)
        expect(response.body).to include(plain.channel_url)
      end

      it "does NOT filter when star=true (yes/no convention is strict)" do
        get channels_path, params: { star: "true" }
        expect(response.body).to include(starred.channel_url)
        expect(response.body).to include(plain.channel_url)
      end

      it "filters by connected=yes" do
        get channels_path, params: { connected: "yes" }
        expect(response.body).to include(connected.channel_url)
        expect(response.body).not_to include(starred.channel_url)
      end

      it "combines star=yes and connected=yes (AND-logic)" do
        both = create(:channel, star: true, connected: true)
        get channels_path, params: { star: "yes", connected: "yes" }
        expect(response.body).to include(both.channel_url)
        expect(response.body).not_to include(starred.channel_url)
        expect(response.body).not_to include(connected.channel_url)
        expect(response.body).not_to include(plain.channel_url)
      end

      it "renders FilterChipComponent for each filter" do
        get channels_path
        # Three filter chips: starred, connected, syncing
        expect(response.body.scan(/class="filter-chip"/).size).to be >= 3
        expect(response.body).to include("md-check-static")
        expect(response.body).to include("md-check-static-label")
      end

      it "marks the active filter chip as [x] in URL state" do
        get channels_path, params: { star: "yes" }
        # The starred chip should now show [x]; others stay [ ]
        expect(response.body).to match(/\[x\][^<]*<\/span>\s*<span class="md-check-static-label">starred/m).or(
          match(/\[x\]<\/span>\s*<span class="md-check-static-label">starred/m)
        )
      end
    end

    context "JSON format" do
      let!(:channel) { create(:channel, :starred) }

      it "returns channel list as JSON with yes/no boolean strings" do
        get channels_path(format: :json)
        json = JSON.parse(response.body)
        expect(json).to be_an(Array)
        row = json.first
        expect(row).to include("id", "tenant_id", "channel_url", "star", "connected", "syncing")
        expect(row["tenant_id"]).to be_a(Integer)
        expect(row["star"]).to eq("yes")
        expect(row["connected"]).to eq("no")
        expect(row["syncing"]).to eq("no")
      end
    end
  end

  describe "GET /channels/:id (show)" do
    let!(:channel) { create(:channel) }

    it "returns 200" do
      get channel_path(channel)
      expect(response).to have_http_status(:ok)
    end

    it "displays channel url" do
      get channel_path(channel)
      expect(response.body).to include(channel.channel_url)
    end

    it "renders [view] external link" do
      get channel_path(channel)
      expect(response.body).to include(">view<")
      expect(response.body).to include('target="_blank"')
    end

    it "includes sync link" do
      get channel_path(channel)
      expect(response.body).to include("/syncs/channel/#{channel.id}")
    end

    it "includes delete link" do
      get channel_path(channel)
      expect(response.body).to include("/deletions/channel/#{channel.id}")
    end

    it "returns 404 for unknown channel" do
      get channel_path(id: 99999)
      expect(response).to have_http_status(:not_found)
    end

    it "returns detail JSON with yes/no strings for boolean flags" do
      get channel_path(channel, format: :json)
      json = JSON.parse(response.body)
      expect(json).to include("id", "tenant_id", "channel_url", "star", "connected", "syncing", "video_count")
      expect(json["tenant_id"]).to be_a(Integer)
      expect(json["star"]).to eq("no")
      expect(json["connected"]).to eq("no")
      expect(json["syncing"]).to eq("no")
    end

    it "returns JSON 404 for unknown channel (not HTML)" do
      get channel_path(id: 99999, format: :json)
      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)).to include("error" => "Not found")
    end

    it "renders inline [star] toggle next to the starred row" do
      get channel_path(channel)
      # The [star] action is inline inside the starred row's value cell
      # (next to "no"), not at the top of the page.
      expect(response.body).to match(/starred<\/td>\s*<td>\s*no\s*<form[^>]*>.*?\[star\].*?<\/form>\s*<\/td>/m)
    end

    it "renders inline [unstar] when channel is already starred" do
      starred = create(:channel, :starred)
      get channel_path(starred)
      expect(response.body).to match(/starred<\/td>\s*<td>\s*yes\s*<form[^>]*>.*?\[unstar\].*?<\/form>\s*<\/td>/m)
    end

    it "renders inline [connect] toggle next to the connected row" do
      get channel_path(channel)
      expect(response.body).to match(/connected<\/td>\s*<td>\s*no\s*<form[^>]*>.*?\[connect\].*?<\/form>\s*<\/td>/m)
    end

    it "renders inline [disconnect] when channel is already connected" do
      connected = create(:channel, :connected)
      get channel_path(connected)
      expect(response.body).to match(/connected<\/td>\s*<td>\s*yes\s*<form[^>]*>.*?\[disconnect\].*?<\/form>\s*<\/td>/m)
    end

    it "does not render the legacy top-of-page star/connect action bar" do
      get channel_path(channel)
      # The toggles moved inline into the table; the top-of-page action row
      # above the pane should no longer include them.
      header_section = response.body.split('<table class="detail-table"').first
      expect(header_section).not_to include("[star]")
      expect(header_section).not_to include("[unstar]")
      expect(header_section).not_to include("[connect]")
      expect(header_section).not_to include("[disconnect]")
    end
  end

  describe "GET /channels/new" do
    it "returns 200" do
      get new_channel_path
      expect(response).to have_http_status(:ok)
    end

    it "shows the URL field with example placeholder" do
      get new_channel_path
      expect(response.body).to include("new channel")
      expect(response.body).to include("https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ")
      expect(response.body).to include("pattern=")
    end

    it "renders only URL field + save/cancel (no starred/connected checkboxes)" do
      get new_channel_path
      expect(response.body).not_to match(/name="channel\[star\]"/)
      expect(response.body).not_to match(/name="channel\[connected\]"/)
      expect(response.body).not_to match(/>\s*starred\s*<\/label>/)
      expect(response.body).not_to match(/>\s*connected\s*<\/label>/)
      expect(response.body).to include("save")
      expect(response.body).to include("cancel")
    end
  end

  describe "POST /channels" do
    it "creates a channel with a valid URL and redirects" do
      expect {
        post channels_path, params: { channel: { channel_url: valid_url } }
      }.to change(Channel, :count).by(1)

      channel = Channel.last
      expect(response).to redirect_to(channel_path(channel))
      expect(channel.channel_url).to eq(valid_url)
    end

    it "enqueues a ChannelSync job after create" do
      expect {
        post channels_path, params: { channel: { channel_url: valid_url } }
      }.to change(ChannelSync.jobs, :size).by(1)
    end

    it "returns 422 on invalid URL" do
      post channels_path, params: { channel: { channel_url: "not-a-url" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns JSON 201 on success" do
      post channels_path(format: :json), params: { channel: { channel_url: valid_url } }
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json).to include("id", "channel_url")
    end

    it "returns JSON 422 with errors on invalid input" do
      post channels_path(format: :json), params: { channel: { channel_url: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["errors"]).to be_an(Array)
    end
  end

  describe "GET /channels/:id/edit" do
    let!(:channel) { create(:channel) }

    it "returns 200" do
      get edit_channel_path(channel)
      expect(response).to have_http_status(:ok)
    end

    it "renders the URL as readonly disabled" do
      get edit_channel_path(channel)
      expect(response.body).to include("readonly")
      expect(response.body).to include("disabled")
      expect(response.body).to include(channel.channel_url)
    end

    it "renders only locked URL + save/cancel (no starred/connected checkboxes)" do
      get edit_channel_path(channel)
      expect(response.body).to include("url is locked after creation.")
      expect(response.body).not_to match(/name="channel\[star\]"\s+type="checkbox"/)
      expect(response.body).not_to match(/name="channel\[connected\]"\s+type="checkbox"/)
      expect(response.body).not_to match(/>\s*starred\s*<\/label>/)
      expect(response.body).not_to match(/>\s*connected\s*<\/label>/)
      expect(response.body).to include("save")
      expect(response.body).to include("cancel")
    end
  end

  describe "PATCH /channels/:id" do
    let!(:channel) { create(:channel) }

    it "permits star and connected as yes/no strings" do
      patch channel_path(channel), params: { channel: { star: "yes", connected: "yes" } }
      expect(response).to redirect_to(channel_path(channel))
      channel.reload
      expect(channel.star).to be(true)
      expect(channel.connected).to be(true)
    end

    it "silently ignores channel_url changes (boundary coercion only reads star/connected)" do
      patch channel_path(channel), params: { channel: { channel_url: other_valid_url, star: "yes" } }
      channel.reload
      expect(channel.channel_url).not_to eq(other_valid_url)
      expect(channel.star).to be(true)
    end

    it "enqueues ChannelSync when toggled to starred" do
      ChannelSync.clear
      expect {
        patch channel_path(channel), params: { channel: { star: "yes" } }
      }.to change(ChannelSync.jobs, :size).by(1)
    end

    it "does not enqueue ChannelSync when un-starring" do
      starred = create(:channel, :starred)
      ChannelSync.clear
      expect {
        patch channel_path(starred), params: { channel: { star: "no" } }
      }.not_to change(ChannelSync.jobs, :size)
    end

    it "JSON success returns 200 and star comes back as yes string" do
      patch channel_path(channel, format: :json), params: { channel: { star: "yes" } }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["star"]).to eq("yes")
    end

    it "JSON rejects raw boolean true with 422" do
      patch channel_path(channel, format: :json), params: { channel: { star: true } }
      expect(response).to have_http_status(:unprocessable_entity)
      channel.reload
      expect(channel.star).to be(false)
    end

    it "JSON rejects star=\"1\" with 422 (legacy values not accepted)" do
      patch channel_path(channel, format: :json), params: { channel: { star: "1" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "JSON rejects star=\"true\" with 422" do
      patch channel_path(channel, format: :json), params: { channel: { star: "true" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "JSON ignores absent star field (no-op update succeeds)" do
      patch channel_path(channel, format: :json), params: { channel: {} }
      expect(response).to have_http_status(:ok)
    end

    context "CSRF (JSON requests)" do
      it "succeeds without an authenticity token (CSRF skipped for JSON)" do
        ActionController::Base.allow_forgery_protection = true
        begin
          patch channel_path(channel, format: :json), params: { channel: { star: "yes" } }
          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json["star"]).to eq("yes")
        ensure
          ActionController::Base.allow_forgery_protection = false
        end
      end

      it "POST .json create succeeds without an authenticity token" do
        ActionController::Base.allow_forgery_protection = true
        begin
          post channels_path(format: :json), params: { channel: { channel_url: valid_url } }
          expect(response).to have_http_status(:created)
        ensure
          ActionController::Base.allow_forgery_protection = false
        end
      end

      it "DELETE .json succeeds without an authenticity token" do
        ActionController::Base.allow_forgery_protection = true
        begin
          delete channel_path(channel, format: :json)
          expect(response).to have_http_status(:no_content)
        ensure
          ActionController::Base.allow_forgery_protection = false
        end
      end
    end
  end

  describe "DELETE /channels/:id" do
    let!(:channel) { create(:channel) }

    it "deletes the channel and redirects" do
      expect {
        delete channel_path(channel)
      }.to change(Channel, :count).by(-1)
      expect(response).to redirect_to(channels_path)
    end

    it "JSON returns 204" do
      channel2 = create(:channel)
      delete channel_path(channel2, format: :json)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET /channels/:id/videos (nested videos)" do
    let!(:channel) { create(:channel) }
    let!(:other_channel) { create(:channel) }
    let!(:video1) { create(:video, channel: channel, title: "first") }
    let!(:video2) { create(:video, channel: channel, title: "second") }
    let!(:other_video) { create(:video, channel: other_channel, title: "other") }

    it "returns 200 JSON with only the videos for that channel" do
      get videos_channel_path(channel, format: :json)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      json = response.parsed_body
      expect(json).to be_an(Array)
      titles = json.map { |v| v["title"] }
      expect(titles).to contain_exactly("first", "second")
      expect(titles).not_to include("other")
    end

    it "returns the video summary shape pito-sh expects" do
      get videos_channel_path(channel, format: :json)
      row = response.parsed_body.first
      expect(row).to include(
        "id", "youtube_video_id", "title", "channel_id", "channel_url",
        "privacy_status", "published_at", "duration_seconds",
        "views", "likes", "comments", "watch_time_minutes", "trend"
      )
    end

    it "returns 404 for an unknown channel" do
      get videos_channel_path(id: 99999, format: :json)
      expect(response).to have_http_status(:not_found)
    end

    it "is reachable without an authentication token" do
      get videos_channel_path(channel, format: :json)
      expect(response).to have_http_status(:ok)
    end

    it "redirects HTML requests to the channel show page" do
      get videos_channel_path(channel)
      expect(response).to redirect_to(channel_path(channel))
    end
  end

  describe "GET /channels/panes (multi-pane)" do
    let!(:channel1) { create(:channel) }
    let!(:channel2) { create(:channel) }

    it "redirects to show when single ID" do
      get panes_channels_path(ids: channel1.id)
      expect(response).to redirect_to(channel_path(channel1))
    end

    it "redirects to index when no IDs" do
      get panes_channels_path(ids: "")
      expect(response).to redirect_to(channels_path)
    end

    it "renders multi-pane view with comma-separated IDs" do
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(channel1.channel_url)
      expect(response.body).to include(channel2.channel_url)
    end

    it "handles unknown IDs gracefully" do
      get "#{panes_channels_path}?ids=#{channel1.id},99999"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("channel not found")
    end

    it "renders a confirm modal (no data-turbo-confirm) for the saved-view delete" do
      url = "/channels/panes?ids=#{channel1.id},#{channel2.id}"
      view = create(:saved_view, kind: :channels, name: "test view", url: url)
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"

      expect(response.body).to include(%(id="confirm-saved-view-#{view.id}"))
      expect(response.body).to include("delete this saved view?")
      expect(response.body).to include('data-controller="modal-trigger"')
      expect(response.body).to include(
        %(data-modal-trigger-target-id-value="confirm-saved-view-#{view.id}")
      )
      expect(response.body).not_to include("data-turbo-confirm")
    end
  end

  describe "model callback integration" do
    it "POST /channels enqueues exactly one ChannelSync" do
      ChannelSync.clear
      post channels_path, params: { channel: { channel_url: valid_url } }
      expect(ChannelSync.jobs.size).to eq(1)
      expect(ChannelSync.jobs.first["args"].first).to eq(Channel.last.id)
    end
  end
end
