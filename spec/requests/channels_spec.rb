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

    it "does not render the legacy [bulk] toggle (always-on checkboxes)" do
      get channels_path
      # Phase B polish (2026-05-05) — checkboxes are always on; the
      # `[bulk]` enter / `[cancel]` exit toggles are gone.
      expect(response.body).not_to match(/\[\s*<span class="bl">bulk<\/span>\s*\]/)
      expect(response.body).not_to include('data-bulk-select-target="bulkToggle"')
    end

    context "with channels" do
      let!(:channel) { create(:channel) }

      it "displays the channel url" do
        get channels_path
        expect(response.body).to include(channel.channel_url)
      end

      it "does not render the YouTube column header (folded into the URL link)" do
        get channels_path
        expect(response.body).not_to match(/<th[^>]*>\s*YouTube\s*</)
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

      it "displays 5 columns (select, Name, URL, star, last sync)" do
        get channels_path
        # Phase B polish (2026-05-05) — select-all + Name + URL + star +
        # last sync. The Name column is a YouTube-sync placeholder rendering
        # `channel.id` as a link until sync populates real titles. The
        # legacy `[o]` open-action column was dropped (post-Wave-3K polish):
        # the Name cell IS the show-page link, so a separate column was
        # redundant. Header text "starred" was shortened to "star" in a
        # 2026-05-06 polish; the underlying sort key stays `starred`.
        thead = response.body.match(/<thead>(.*?)<\/thead>/m)[1]
        expect(thead.scan(/<th\b/).size).to eq(5)
      end

      # Phase 4 Wave 3 — Name column. Placeholder for the YouTube channel
      # title once sync lands. The cell currently renders `channel.id` as a
      # link to the show page so the column has stable content. Header is a
      # server-side sort link (`?sort=id&dir=<asc|desc>`), aligning with the
      # `/projects` index pattern.
      it "renders a Name column header at column 2 (after the checkbox)" do
        get channels_path
        thead = response.body.match(/<thead>(.*?)<\/thead>/m)[1]
        # Pull the <th> elements in order. Column 1 is the select-all
        # checkbox header; column 2 must be `Name`.
        ths = Nokogiri::HTML.fragment(thead).css("th")
        expect(ths.length).to eq(5)
        # The header text reads "Name" (with an optional ▲/▼ when active).
        expect(ths[1].text.strip).to start_with("Name")
      end

      it "renders the Name header as a server-side sort link with sort + dir params" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip.start_with?("Name") }
        expect(link).not_to be_nil
        # Default state is `created_at desc`, so clicking Name should request
        # `id asc`.
        expect(link["href"]).to include("sort=id")
        expect(link["href"]).to include("dir=asc")
        # No more client-side Stimulus action attribute on the header.
        expect(link.to_html).not_to include("click->sortable-table#sort")
      end

      it "renders the Name cell as a link to the channel show page" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").first
        # Column index 1 (0-based) — second <td>, after the checkbox cell.
        name_cell = row.css("td")[1]
        link = name_cell.css("a").first
        expect(link).not_to be_nil
        expect(link["href"]).to eq(channel_path(channel))
        expect(link.text.strip).to eq(channel.id.to_s)
      end

      it "exposes `id` in ChannelsController::ALLOWED_SORTS so server-side sort honors it" do
        # The Name column header sort link uses `?sort=id`; the constant
        # mapping must include the key for that URL to round-trip.
        expect(ChannelsController::ALLOWED_SORTS).to include("id" => "channels.id")
      end

      it "renders a non-sortable URL header (URL is the YouTube link itself)" do
        get channels_path
        thead = response.body.match(/<thead>(.*?)<\/thead>/m)[1]
        expect(thead).to match(/<th>URL<\/th>/)
        # No <a> inside the URL <th> (sortable headers wrap the label in <a>).
        url_th = Nokogiri::HTML.fragment(thead).css("th").find { |th| th.text.strip == "URL" }
        expect(url_th.css("a")).to be_empty
      end

      it "renders the URL cell as an external YouTube link with target=_blank" do
        get channels_path
        # The URL text itself is now the external link (no separate [v]).
        # Post-consolidation: the link text is a server-side
        # middle-truncated single string (`https://…<tail>`) — same
        # shape used by the footage filename column and the videos
        # channel-URL column.
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("a").find { |a| a["href"] == channel.channel_url }
        expect(link).not_to be_nil
        expect(link["target"]).to eq("_blank")
        expect(link["rel"]).to eq("noopener noreferrer")
        # The link text is the truncated form, not the raw URL.
        expect(link.text).to include("…")
      end

      # Post-consolidation — URL cell middle-truncation. Returns a
      # single fixed-length string `<head>…<tail>` (e.g.
      # `https://…jF7eS8r1` for an 8/8 split) so the unique channel ID
      # at the end of `https://www.youtube.com/channel/<id>` stays
      # visible without spanning the column. The `<td>` wears a
      # `title=<full URL>` for hover-reveal. Same shape as the videos
      # channel-URL column and the footage filename column.
      it "renders the URL cell as a single truncated text node with a title attribute" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        # Locate the URL <td> — third cell in the first body row
        # (checkbox / Name / URL / star / last sync).
        row = html.css("tbody tr").first
        url_cell = row.css("td")[2]
        expect(url_cell["title"]).to eq(channel.channel_url)
        link = url_cell.css("a").first
        expect(link).not_to be_nil
        expect(link["href"]).to eq(channel.channel_url)
        # The link's text is the head/tail string with a U+2026
        # ellipsis joining them.
        expect(link.text).to start_with("https://")
        expect(link.text).to include("…")
        expect(link.text.length).to eq(8 + 1 + 8) # head + ellipsis + tail
        expect(link.text).to end_with(channel.channel_url[-8..])
        # No two-span flex markup left over from the prior pattern.
        expect(url_cell.css(".middle-truncate-head")).to be_empty
        expect(url_cell.css(".middle-truncate-tail")).to be_empty
      end

      it "renders a sortable star column header (lowercase, no star icon)" do
        # Header text was shortened from "starred" to "star" (2026-05-06
        # polish) to mirror the [star] / [unstar] action vocabulary used
        # elsewhere; the underlying sort key stays `starred`.
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip.start_with?("star") }
        expect(link).not_to be_nil
        expect(link.text.strip).to start_with("star")
        expect(link.text.strip).not_to include("starred")
        expect(link["href"]).to include("sort=starred")
        # Wrapped in the right `<th class="sortable num">` for layout.
        expect(link.parent.name).to eq("th")
        expect(link.parent["class"]).to include("sortable")
        expect(link.parent["class"]).to include("num")
        expect(response.body).not_to include("★")
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

      it "no longer ships a separate [v] action column (folded into the URL link)" do
        get channels_path
        # The URL cell IS the external link now; no standalone `[v]`
        # button exists in the row markup.
        expect(response.body).not_to include('class="bl">v</span>')
        # target=_blank still appears via the URL <a> tag, just not via [v].
        expect(response.body).to include('target="_blank"')
      end

      it "renders always-on bulk select controls (no toggle)" do
        get channels_path
        expect(response.body).to include('data-bulk-select-target="checkbox"')
        expect(response.body).to include('data-bulk-select-target="headerCheckbox"')
        expect(response.body).to include('data-bulk-select-max-panes-value="3"')
        # Header + row checkboxes ship without `hidden` (always visible now).
        expect(response.body).not_to match(/data-bulk-select-target="bulkCol"\s+hidden/)
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

    # Phase 4 Wave 3 — server-side sort via `?sort=<key>&dir=<asc|desc>`.
    # Replaces the client-side Stimulus `sortable-table` controller for the
    # index view (the controller still serves the per-pane video tables).
    # Mirrors `/projects` URL-state sort.
    context "URL-state sort" do
      let!(:older) { create(:channel, created_at: 2.days.ago) }
      let!(:newer) { create(:channel, created_at: 1.day.ago) }

      it "defaults to created_at DESC (newest first)" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        ids = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| t.match?(/\A\d+\z/) }.uniq
        expect(ids).to eq([ newer.id.to_s, older.id.to_s ])
      end

      it "sorts by id ASC when called with ?sort=id&dir=asc" do
        get channels_path, params: { sort: "id", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        ids = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| t.match?(/\A\d+\z/) }.uniq
        expect(ids).to eq(ids.sort_by(&:to_i))
      end

      it "sorts by id DESC when called with ?sort=id&dir=desc" do
        get channels_path, params: { sort: "id", dir: "desc" }
        html = Nokogiri::HTML.fragment(response.body)
        ids = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| t.match?(/\A\d+\z/) }.uniq
        expect(ids).to eq(ids.sort_by(&:to_i).reverse)
      end

      it "renders the active-sort indicator (▼) on the active column header" do
        get channels_path, params: { sort: "id", dir: "desc" }
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip.start_with?("Name") }
        expect(link.text).to include("▼")
      end

      it "renders the active-sort indicator (▲) when dir=asc" do
        get channels_path, params: { sort: "id", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip.start_with?("Name") }
        expect(link.text).to include("▲")
      end

      it "ignores unknown sort keys and falls back to created_at" do
        get channels_path, params: { sort: "drop_table_channels", dir: "asc" }
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML.fragment(response.body)
        # Default fallback is created_at + caller's `dir=asc` — older first.
        ids = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| t.match?(/\A\d+\z/) }.uniq
        expect(ids.first).to eq(older.id.to_s)
      end

      it "ignores unknown dir values and falls back to desc" do
        get channels_path, params: { sort: "id", dir: "sideways" }
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML.fragment(response.body)
        ids = html.css("tbody tr td a").map { |a| a.text.strip }.select { |t| t.match?(/\A\d+\z/) }.uniq
        expect(ids).to eq(ids.sort_by(&:to_i).reverse)
      end

      it "toggles direction when the same column is clicked twice" do
        # First request — default state. The Name link should request `asc`.
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip.start_with?("Name") }
        expect(link["href"]).to include("dir=asc")

        # Second request — caller is now on `sort=id dir=asc`. The link should
        # offer the opposite direction.
        get channels_path, params: { sort: "id", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip.start_with?("Name") }
        expect(link["href"]).to include("dir=desc")
      end

      # Filter + sort interaction. Filter chips emit URLs like `?starred=yes`;
      # sort header links must merge BOTH filter params AND new sort params
      # so neither dimension clobbers the other.
      it "preserves filter params when re-sorting (filter + sort both apply)" do
        starred1 = create(:channel, :starred, created_at: 4.days.ago)
        starred2 = create(:channel, :starred, created_at: 3.days.ago)

        get channels_path, params: { star: "yes", sort: "id", dir: "asc" }
        expect(response).to have_http_status(:ok)
        # Only starred channels render — filter applied.
        expect(response.body).to include(starred1.channel_url)
        expect(response.body).to include(starred2.channel_url)
        expect(response.body).not_to include(older.channel_url)
        expect(response.body).not_to include(newer.channel_url)

        # Header sort links carry the active `star=yes` filter alongside
        # the next-direction sort params, so re-clicking a header preserves
        # the filter. The header text reads "star" (shortened from
        # "starred" in the 2026-05-06 polish) but the sort key stays
        # `starred` — that's the column name in the database.
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip.start_with?("star") }
        expect(link["href"]).to include("star=yes")
        expect(link["href"]).to include("sort=starred")
        # Currently sorting by id asc, not by starred — so star header
        # offers `dir=asc` (its first click direction).
        expect(link["href"]).to include("dir=asc")
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

    it "renders [v] external link" do
      get channel_path(channel)
      expect(response.body).to include('class="bl">v</span>')
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

    # Phase B revamp (2026-05-05) — single-pane show wraps the pane in
    # the standard pane-container/pane-wrapper scaffolding so the global
    # `:only-child` rule paints the wrapper with `--color-pane-bg-wide`
    # (the standalone tone), reading as visually distinct from the A/B
    # alternation used in multi-pane workspace views.
    it "wraps the single pane in pane-container > pane-wrapper" do
      get channel_path(channel)
      expect(response.body).to include('<div class="pane-container">')
      expect(response.body).to match(/<div class="pane-container">\s*<div class="pane-wrapper">/)
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

    it "renders only URL field + add/cancel (no starred/connected checkboxes)" do
      get new_channel_path
      expect(response.body).not_to match(/name="channel\[star\]"/)
      expect(response.body).not_to match(/name="channel\[connected\]"/)
      expect(response.body).not_to match(/>\s*starred\s*<\/label>/)
      expect(response.body).not_to match(/>\s*connected\s*<\/label>/)
      expect(response.body).to include("[<b>add</b>]")
      expect(response.body).not_to include("[<b>update</b>]")
      expect(response.body).to include("cancel")
    end

    it "renders the breadcrumb tail as [add] (no entity word)" do
      get new_channel_path
      expect(response.body).to include('<span class="bracketed-active">[add]</span>')
      expect(response.body).not_to include('[add channel]')
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

    it "renders only locked URL + update/cancel (no starred/connected checkboxes)" do
      get edit_channel_path(channel)
      expect(response.body).to include("URL is locked after creation.")
      expect(response.body).not_to match(/name="channel\[star\]"\s+type="checkbox"/)
      expect(response.body).not_to match(/name="channel\[connected\]"\s+type="checkbox"/)
      expect(response.body).not_to match(/>\s*starred\s*<\/label>/)
      expect(response.body).not_to match(/>\s*connected\s*<\/label>/)
      expect(response.body).to include("[<b>update</b>]")
      expect(response.body).not_to include("[<b>add</b>]")
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

    it "shows save button when no saved view exists" do
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      expect(response.body).to include('class="bl">save</span>')
      expect(response.body).not_to include('class="bl">update</span>')
    end

    # Phase B revamp (2026-05-05) — multi-pane view emits N pane-wrappers
    # in a single pane-container. The global CSS handles A/B alternation
    # via `:nth-child(odd)`/`:nth-child(even)`; the view itself stays
    # markup-only — every pane carries `class="pane-wrapper"` and the
    # browser paints them. Asserting via the marker count keeps the test
    # decoupled from the per-pane decoration (arrows, headings).
    it "renders one .pane-wrapper per channel inside a single .pane-container" do
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      containers = response.body.scan(/class="pane-container"/).size
      wrappers   = response.body.scan(/class="pane-wrapper"/).size
      expect(containers).to eq(1)
      expect(wrappers).to eq(2)
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
