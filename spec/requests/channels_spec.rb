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

      # Phase 7 Path A2 — `syncing` is gone entirely (column dropped)
      it "does not render a separate syncing column header" do
        get channels_path
        expect(response.body).not_to match(/<th[^>]*>\s*syncing\s*</)
      end

      # Post-cleanup — every channel is OAuth-linked by definition, so
      # neither the legacy `syncing` filter chip nor the derived
      # `connected` filter chip exists.
      it "does not render the syncing filter chip" do
        get channels_path
        expect(response.body).not_to match(/md-check-static-label">syncing/)
      end

      it "does not render the connected filter chip" do
        get channels_path
        expect(response.body).not_to match(/md-check-static-label">connected/)
      end

      it "displays 8 columns (select, avatar, name, URL, subscribers, videos, star, last sync)" do
        get channels_path
        # Phase 24+ density pass (2026-05-10) — the prior 5-column
        # placeholder was widened to surface the sync-populated metadata:
        # avatar, title + `@handle`, full `/@handle` URL, subscriber
        # count (with "Hidden" treatment), video count, star, last sync.
        # The avatar column is intentionally header-label-less (narrow
        # decorative column).
        thead = response.body.match(/<thead>(.*?)<\/thead>/m)[1]
        expect(thead.scan(/<th\b/).size).to eq(8)
      end

      # Phase 4 Wave 3 — name column. Placeholder for the YouTube channel
      # title once sync lands. The cell currently renders `channel.id` as a
      # link to the show page so the column has stable content. Header is a
      # server-side sort link (`?sort=id&dir=<asc|desc>`), aligning with the
      # `/projects` index pattern.
      it "renders a lowercase `name` column header at column 3 (after checkbox + avatar)" do
        get channels_path
        thead = response.body.match(/<thead>(.*?)<\/thead>/m)[1]
        # Pull the <th> elements in order. Column 1 is the select-all
        # checkbox header; column 2 is the (label-less) avatar header;
        # column 3 must be `name` (lowercase).
        ths = Nokogiri::HTML.fragment(thead).css("th")
        expect(ths.length).to eq(8)
        # The header text reads "name" — the directional arrow now rides
        # via CSS `::after`, so the link text is just the label.
        expect(ths[2].text.strip).to eq("name")
        # And NOT the legacy "Name" capitalization.
        expect(ths[2].text.strip).not_to start_with("Name")
      end

      it "renders the name header as a server-side sort link with sort + dir params" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip == "name" }
        expect(link).not_to be_nil
        # Default state is `created_at desc`, so clicking name should request
        # `id asc`.
        expect(link["href"]).to include("sort=id")
        expect(link["href"]).to include("dir=asc")
        # No more client-side Stimulus action attribute on the header.
        expect(link.to_html).not_to include("click->sortable-table#sort")
      end

      it "renders the name cell as a link to the channel show page" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").first
        # Column index 2 (0-based) — third <td>, after the checkbox +
        # avatar cells.
        name_cell = row.css("td")[2]
        link = name_cell.css("a").first
        expect(link).not_to be_nil
        expect(link["href"]).to eq(channel_path(channel))
        # When `title` is nil (pre-sync rows — the default factory),
        # the link falls back to the channel id as the visible label
        # so the column stays scannable.
        expect(link.text.strip).to eq(channel.id.to_s)
      end

      # Turbo Frames bugfix (2026-05-06) — the channel id link sits
      # INSIDE `<turbo-frame id='channels-index-table'>` but the show
      # page has no matching frame. Stamp `data-turbo-frame=_top` so
      # the click escapes the frame and does a full-page navigation.
      it "stamps data-turbo-frame=_top on the channel name link (escape the frame on row click)" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").first
        name_cell = row.css("td")[2]
        link = name_cell.css("a").first
        expect(link["data-turbo-frame"]).to eq("_top")
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
        # Phase 24+ density pass — the URL cell renders the full
        # display URL (either `/@handle` or UC-id fallback) with no
        # truncation. For factory rows the handle is nil, so the
        # fallback equals the locked `channel_url` (the UC-id form).
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("a").find { |a| a["href"] == channel.channel_url }
        expect(link).not_to be_nil
        expect(link["target"]).to eq("_blank")
        expect(link["rel"]).to eq("noopener noreferrer")
        # No truncation — the link text is the full URL.
        expect(link.text).not_to include("…")
        expect(link.text).to eq(channel.channel_url)
      end

      # Phase 24+ density pass — URL cell no longer truncates. The
      # `<td>` is the 4th body cell (checkbox / avatar / name / URL /
      # subscribers / videos / star / last sync) and renders the full
      # display URL as both the `href` and link text. For factory rows
      # the handle is nil, so the display URL is the UC-id form (the
      # locked `channel_url`).
      it "renders the URL cell as the full URL with no truncation" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").first
        url_cell = row.css("td")[3]
        link = url_cell.css("a").first
        expect(link).not_to be_nil
        expect(link["href"]).to eq(channel.channel_url)
        expect(link.text).to eq(channel.channel_url)
        expect(link.text).not_to include("…")
        # No middle-truncate spans left over from the prior pattern.
        expect(url_cell.css(".middle-truncate-head")).to be_empty
        expect(url_cell.css(".middle-truncate-tail")).to be_empty
      end

      it "renders the @handle URL form when the channel has a handle" do
        with_handle = create(
          :channel,
          handle: "@pitomdtest",
          title: "Pito MD Test"
        )
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("a").find { |a| a["href"] == "https://www.youtube.com/@pitomdtest" }
        expect(link).not_to be_nil
        expect(link.text).to eq("https://www.youtube.com/@pitomdtest")
        # Sanity — the raw `channel_url` (UC-id form) is NOT used
        # when the @handle URL is available.
        raw_link = html.css("a").find { |a| a["href"] == with_handle.channel_url }
        expect(raw_link).to be_nil
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

      # Phase 24+ density pass — avatar column. 2nd cell of each row;
      # renders an `<img>` with class `.avatar-thumb` when `avatar_url`
      # is present, a muted em-dash placeholder otherwise. The factory
      # row has no avatar (pre-sync), so this base case exercises the
      # fallback.
      it "renders an em-dash in the avatar cell when avatar_url is nil" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").first
        avatar_cell = row.css("td")[1]
        expect(avatar_cell["class"]).to include("avatar-cell")
        expect(avatar_cell.text.strip).to eq("—")
        expect(avatar_cell.css("img")).to be_empty
      end

      it "renders a .avatar-thumb <img> in the avatar cell when avatar_url is present" do
        with_avatar = create(:channel, avatar_url: "https://example.test/a.jpg")
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").find do |tr|
          tr.css("a").any? { |a| a["href"] == with_avatar.channel_url || a["href"]&.include?(with_avatar.id.to_s) }
        end
        expect(row).not_to be_nil
        avatar_cell = row.css("td")[1]
        img = avatar_cell.css("img").first
        expect(img).not_to be_nil
        expect(img["src"]).to eq("https://example.test/a.jpg")
        expect(img["class"]).to include("avatar-thumb")
      end

      # Phase 24+ distortion-fix (2026-05-10) — defensive HTML attrs so
      # the table cell reserves the intrinsic 32×32 box before the image
      # loads. Without these the table cell could stretch the image
      # vertically (narrow silhouettes) during paint. CSS handles the
      # final clip (object-fit + border-radius); the HTML attributes
      # are a belt-and-braces guard.
      it "renders the avatar <img> with explicit width=32 height=32 HTML attributes" do
        with_avatar = create(:channel, avatar_url: "https://example.test/a.jpg")
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").find do |tr|
          tr.css("a").any? { |a| a["href"] == with_avatar.channel_url || a["href"]&.include?(with_avatar.id.to_s) }
        end
        expect(row).not_to be_nil
        img = row.css("td")[1].css("img").first
        expect(img).not_to be_nil
        expect(img["width"]).to eq("32")
        expect(img["height"]).to eq("32")
      end

      it "marks the avatar <img> as lazy-loaded" do
        with_avatar = create(:channel, avatar_url: "https://example.test/a.jpg")
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").find do |tr|
          tr.css("a").any? { |a| a["href"] == with_avatar.channel_url || a["href"]&.include?(with_avatar.id.to_s) }
        end
        expect(row).not_to be_nil
        img = row.css("td")[1].css("img").first
        expect(img).not_to be_nil
        expect(img["loading"]).to eq("lazy")
      end

      # Phase 24+ density pass — subscriber column (5th cell). Uses
      # the `formatted_subscriber_count` helper, which delegates to
      # `number_with_delimiter` and renders "Hidden" when the channel
      # has `hidden_subscriber_count: true`.
      it "renders the delimited subscriber count when set" do
        with_subs = create(:channel, subscriber_count: 12_345)
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").find do |tr|
          tr.css("a").any? { |a| a["href"]&.include?(with_subs.to_param) }
        end
        expect(row).not_to be_nil
        subs_cell = row.css("td")[4]
        expect(subs_cell.text.strip).to eq("12,345")
        expect(subs_cell["class"]).to include("num")
      end

      it "renders 'Hidden' in the subscriber cell when hidden_subscriber_count is true" do
        hidden = create(:channel, subscriber_count: 99_999, hidden_subscriber_count: true)
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").find do |tr|
          tr.css("a").any? { |a| a["href"]&.include?(hidden.to_param) }
        end
        expect(row).not_to be_nil
        subs_cell = row.css("td")[4]
        expect(subs_cell.text.strip).to eq("Hidden")
      end

      # Video count column (6th cell). Same helper pattern — delimited
      # integer or em-dash placeholder when nil.
      it "renders the delimited video count when set" do
        with_videos = create(:channel, video_count: 1_234)
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").find do |tr|
          tr.css("a").any? { |a| a["href"]&.include?(with_videos.to_param) }
        end
        expect(row).not_to be_nil
        videos_cell = row.css("td")[5]
        expect(videos_cell.text.strip).to eq("1,234")
        expect(videos_cell["class"]).to include("num")
      end

      it "renders the em-dash placeholder in the video count cell when nil" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").first
        videos_cell = row.css("td")[5]
        expect(videos_cell.text.strip).to eq("—")
      end

      # Title + @handle rendering in the name cell. When the channel
      # has a `title`, the link text is the title (not the id), and a
      # muted `@handle` sub-line renders below the link.
      it "renders the title as the name link text and @handle as muted sub-text" do
        rich = create(:channel, title: "Pito MD Test", handle: "@pitomdtest")
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").find do |tr|
          tr.css("a").any? { |a| a["href"]&.include?(rich.to_param) }
        end
        expect(row).not_to be_nil
        name_cell = row.css("td")[2]
        link = name_cell.css("a").first
        expect(link.text.strip).to eq("Pito MD Test")
        # Muted handle sub-text on its own line.
        muted = name_cell.css(".text-muted").first
        expect(muted).not_to be_nil
        expect(muted.text.strip).to eq("@pitomdtest")
      end

      it "renders the new column headers (avatar blank, subscribers, videos)" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        headers = html.css("thead th").map { |th| th.text.strip }
        # The avatar header has no label.
        expect(headers).to eq([ "", "", "name", "URL", "subscribers", "videos", "star", "last sync" ])
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
        # Phase 20 — friendly URLs: links use the channel's slug
        # (`to_param`), not the integer id.
        expect(response.body).to include("/channels/#{channel.to_param}")
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
      # with a dangling `· [cancel]`.
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

      # Frame-escape regression guard (2026-05-10). The channels table
      # sits inside `<turbo-frame id="channels-index-table">` so sortable
      # headers and filter chips can partial-swap. Without
      # `data-turbo-frame="_top"` cascading on the bulk-toolbar actions
      # container, the controller-injected `[open N]` / `[sync N]` /
      # `[delete N]` links would navigate the click inside that frame —
      # those targets are full-page surfaces (panes workspace,
      # `shared/_action_screen.html.erb`) and have no matching frame in
      # their responses, so Turbo would render "Content missing".
      it "stamps data-turbo-frame=_top on the bulk-toolbar actions container" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        actions = html.css('[data-bulk-select-target="actions"]').first
        expect(actions).not_to be_nil, "expected the bulk-select actions container"
        expect(actions["data-turbo-frame"]).to eq("_top"),
          "bulk-toolbar must escape the channels-index-table frame so [open N] / [sync N] / [delete N] navigate full-page"
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

      # Polish-2 (2026-05-06) — active-column indicator now rendered via
      # CSS `::after` on the parent `<th>`, driven by the `sort-asc` /
      # `sort-desc` class on the inner `<a>`. The link text is just the
      # bare label so active and inactive headers line up identically.
      it "stamps a `sort-desc` class on the active column link when dir=desc" do
        get channels_path, params: { sort: "id", dir: "desc" }
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip == "name" }
        expect(link["class"].to_s.split).to include("sort-desc")
      end

      it "stamps a `sort-asc` class on the active column link when dir=asc" do
        get channels_path, params: { sort: "id", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip == "name" }
        expect(link["class"].to_s.split).to include("sort-asc")
      end

      it "does not render an inline ▲ / ▼ glyph in the active link's text" do
        get channels_path, params: { sort: "id", dir: "desc" }
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip == "name" }
        expect(link.text).not_to include("▲")
        expect(link.text).not_to include("▼")
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
        # First request — default state. The name link should request `asc`.
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip == "name" }
        expect(link["href"]).to include("dir=asc")

        # Second request — caller is now on `sort=id dir=asc`. The link should
        # offer the opposite direction.
        get channels_path, params: { sort: "id", dir: "asc" }
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip == "name" }
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
      let!(:starred) { create(:channel, :starred) }
      let!(:plain)   { create(:channel) }

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

      it "silently ignores connected=yes (the filter no longer exists)" do
        connection = create(:youtube_connection)
        oauth_linked = create(:channel, youtube_connection: connection)
        get channels_path, params: { connected: "yes" }
        # All channels render — `connected` is no longer a filter key.
        expect(response.body).to include(oauth_linked.channel_url)
        expect(response.body).to include(starred.channel_url)
        expect(response.body).to include(plain.channel_url)
      end

      it "renders FilterChipComponent for each remaining filter" do
        get channels_path
        # Post-cleanup — only the `starred` chip remains; the legacy
        # `syncing` and the derived `connected` chips are both gone.
        expect(response.body.scan(/class="filter-chip"/).size).to eq(1)
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
        # The derived `connected` field and the legacy `syncing` field
        # are both retired from the JSON wire shape.
        expect(row).to include("id", "channel_url", "star")
        expect(row).not_to have_key("syncing")
        expect(row).not_to have_key("tenant_id")
        expect(row).not_to have_key("connected")
        expect(row["star"]).to eq("yes")
      end
    end

    # Polish-3 (2026-05-06) — Turbo Frame wrapper around the channels
    # table + bulk toolbar. Sort-header clicks and filter-chip toggles
    # target this frame so only the table region re-renders on the
    # page. Combined with `data-turbo-action=advance`, the URL still
    # updates and back/forward navigation works. The frame element must
    # be present on every render (including the empty state) so Turbo
    # can match the response and skip the fall-back to a full-page
    # navigation.
    describe "turbo-frame wrapper" do
      it "wraps the empty state in <turbo-frame id='channels-index-table'>" do
        get channels_path
        html = Nokogiri::HTML.fragment(response.body)
        frame = html.css("turbo-frame#channels-index-table").first
        expect(frame).not_to be_nil
      end

      context "with channels" do
        let!(:channel) { create(:channel) }

        it "wraps the table inside <turbo-frame id='channels-index-table'>" do
          get channels_path
          html = Nokogiri::HTML.fragment(response.body)
          frame = html.css("turbo-frame#channels-index-table").first
          expect(frame).not_to be_nil
          expect(frame.css("table")).not_to be_empty
        end

        it "stamps data-turbo-frame=channels-index-table on every sort link" do
          get channels_path
          html = Nokogiri::HTML.fragment(response.body)
          sort_links = html.css("turbo-frame#channels-index-table thead a")
          expect(sort_links).not_to be_empty
          sort_links.each do |a|
            expect(a["data-turbo-frame"]).to eq("channels-index-table"),
              "expected data-turbo-frame on sort link #{a.text.strip.inspect}"
            expect(a["data-turbo-action"]).to eq("advance"),
              "expected data-turbo-action=advance on sort link #{a.text.strip.inspect}"
          end
        end

        # Inverse of the row-link `_top` rule: sort header clicks should
        # re-render the frame, NOT escape to a full-page navigation.
        # Regression guard against widening sort scope by accident.
        it "does NOT stamp data-turbo-frame=_top on any sort header link" do
          get channels_path
          html = Nokogiri::HTML.fragment(response.body)
          sort_links = html.css("turbo-frame#channels-index-table thead a")
          expect(sort_links).not_to be_empty
          sort_links.each do |a|
            expect(a["data-turbo-frame"]).not_to eq("_top"),
              "sort link #{a.text.strip.inspect} must stay frame-scoped, not escape to _top"
          end
        end

        it "stamps data-turbo-frame=channels-index-table on every filter chip" do
          get channels_path
          html = Nokogiri::HTML.fragment(response.body)
          chips = html.css("a.filter-chip")
          expect(chips).not_to be_empty
          chips.each do |a|
            expect(a["data-turbo-frame"]).to eq("channels-index-table"),
              "expected data-turbo-frame on filter chip #{a.text.strip.inspect}"
            expect(a["data-turbo-action"]).to eq("advance"),
              "expected data-turbo-action=advance on filter chip #{a.text.strip.inspect}"
          end
        end

        it "stamps data-turbo-frame=channels-index-table on the [clear] link when a filter is active" do
          starred = create(:channel, :starred)
          get channels_path, params: { star: "yes" }
          html = Nokogiri::HTML.fragment(response.body)
          # The `[clear]` link is a BracketedLinkComponent; its rendered
          # markup is `<a class="bracketed">[<span class="bl">clear</span>]</a>`.
          clear_link = html.css("a.bracketed").find { |a| a.css("span.bl").any? { |s| s.text.strip == "clear" } }
          expect(clear_link).not_to be_nil, "expected a [clear] link with at least one channel filter active"
          expect(clear_link["data-turbo-frame"]).to eq("channels-index-table")
          expect(clear_link["data-turbo-action"]).to eq("advance")
          expect(starred.persisted?).to be true
        end
      end
    end
  end

  # Keyboard-navigation opt-in (2026-05-10): each channel row carries
  # `data-keyboard-row` + `data-keyboard-row-id` so the global keyboard
  # controller's `j`/`k` highlight, `space` toggle, and `D`/`Y` bulk
  # actions resolve against the row's channel id. Mirrors the hook on
  # notifications and schedule rows.
  describe "keyboard-row markup" do
    let!(:channel_a) { create(:channel, channel_url: valid_url) }
    let!(:channel_b) { create(:channel, channel_url: other_valid_url) }

    it "tags each channel row with data-keyboard-row + data-keyboard-row-id" do
      get channels_path
      html = Nokogiri::HTML.fragment(response.body)
      rows = html.css("tbody tr[data-keyboard-row]")
      expect(rows.size).to eq(2)
      ids = rows.map { |r| r["data-keyboard-row-id"] }.sort
      expect(ids).to eq([ channel_a.id.to_s, channel_b.id.to_s ].sort)
    end

    it "leaves the empty-state body without keyboard-row markup" do
      Channel.delete_all
      get channels_path
      expect(response.body).not_to include("data-keyboard-row")
    end
  end

  # The full HTML rendering matrix for `/channels/:slug` lives in
  # `spec/requests/channels_show_spec.rb` (Phase 7.5 §11b — show page
  # revamp). The block below keeps the load-bearing controller-level
  # contracts that survive the revamp: 200, sync link, delete link,
  # JSON shape, 404, and the add-pane `[+]` button.
  describe "GET /channels/:id (show)" do
    let!(:channel) { create(:channel) }

    it "returns 200" do
      get channel_path(channel)
      expect(response).to have_http_status(:ok)
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
      # The derived `connected` field and the legacy `syncing` /
      # `tenant_id` fields are all retired from the JSON wire shape.
      expect(json).to include("id", "channel_url", "star", "video_count")
      expect(json).not_to have_key("syncing")
      expect(json).not_to have_key("tenant_id")
      expect(json).not_to have_key("connected")
      expect(json["star"]).to eq("no")
    end

    it "returns JSON 404 for unknown channel (not HTML)" do
      get channel_path(id: 99999, format: :json)
      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)).to include("error" => "Not found")
    end

    # Copy fix (2026-05-10) — the heading row's add-pane trigger renders
    # as `[+]` (not `[|]`). The action is unchanged (opens the add-pane
    # modal via `click->add-pane#open`); only the displayed glyph is `+`.
    it "renders the heading-row add-pane trigger as [+] (not [|])" do
      create(:channel) # ensure @available_channels.any? so the button renders
      get channel_path(channel)
      expect(response.body).to match(%r{\[<span class="bl">\+</span>\]})
      expect(response.body).not_to match(%r{\[<span class="bl">\|</span>\]})
    end
  end

  # The URL-paste entry path was dropped — channels enter the system
  # exclusively through the Google OAuth + channel-selection flow at
  # /settings/youtube. `GET /channels/new` and the user-facing
  # `POST /channels` are no longer routed; the `new_channel_path`
  # helper does not exist; the `[+]` button on /channels points to
  # /settings/youtube.
  describe "URL-paste entry path is dropped" do
    it "does not expose the `new_channel_path` helper" do
      expect(Rails.application.routes.url_helpers)
        .not_to respond_to(:new_channel_path)
    end

    it "GET /channels/new no longer routes to channels#new" do
      # The `:new` route was dropped from `resources :channels`. The
      # remaining `/channels/:id` route is greedy enough to swallow
      # `/channels/new` (with `id: "new"`), which then 404s in the
      # show action when FriendlyId fails to resolve. Either way the
      # URL-paste form is unreachable.
      route = Rails.application.routes.recognize_path("/channels/new", method: :get)
      expect(route[:action]).not_to eq("new")
      expect(route[:action]).to eq("show")

      # In the test env Rails' rescue_from converts RecordNotFound to
      # a 404 by default; the URL-paste form is unreachable either
      # way. Asserting the action != "new" is the real contract here.
    end

    it "does not match POST /channels under recognize_path" do
      expect {
        Rails.application.routes.recognize_path("/channels", method: :post)
      }.to raise_error(ActionController::RoutingError)
    end

    # Phase 24 — the `[+]` button no longer routes to /settings/youtube
    # (the page is gone, 301-redirecting to /channels). It now submits
    # a POST form to /channels/connect_google (the new request-phase
    # OAuth entry point on this controller).
    it "renders the [+] button posting to /channels/connect_google" do
      get channels_path
      expect(response.body).to match(
        %r{<form[^>]*action="#{Regexp.escape(connect_google_channels_path)}"[^>]*method="post"}
      )
      expect(response.body).to include('class="bracketed">[<span class="bl">+</span>]</button>')
    end

    it "renders the empty-state copy pointing at the Google banner" do
      Channel.delete_all
      get channels_path
      expect(response.body).to include("no channels yet")
      expect(response.body).to include("Google banner above")
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

    # Phase 7 Path A2 — the `connected` boolean is gone; only `star`
    # is mutable through PATCH /channels/:id. Connection state is
    # OAuth-managed at /settings/youtube.
    it "permits star as a yes/no string" do
      patch channel_path(channel), params: { channel: { star: "yes" } }
      expect(response).to redirect_to(channel_path(channel))
      channel.reload
      expect(channel.star).to be(true)
    end

    it "silently ignores channel_url changes (boundary coercion only reads star)" do
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
      expect(response).to have_http_status(:unprocessable_content)
      channel.reload
      expect(channel.star).to be(false)
    end

    it "JSON rejects star=\"1\" with 422 (legacy values not accepted)" do
      patch channel_path(channel, format: :json), params: { channel: { star: "1" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "JSON rejects star=\"true\" with 422" do
      patch channel_path(channel, format: :json), params: { channel: { star: "true" } }
      expect(response).to have_http_status(:unprocessable_content)
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
    let!(:video1) { create(:video, channel: channel) }
    let!(:video2) { create(:video, channel: channel) }
    let!(:other_video) { create(:video, channel: other_channel) }

    it "returns 200 JSON with only the videos for that channel" do
      get videos_channel_path(channel, format: :json)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      json = response.parsed_body
      expect(json).to be_an(Array)
      youtube_ids = json.map { |v| v["youtube_video_id"] }
      expect(youtube_ids).to contain_exactly(video1.youtube_video_id, video2.youtube_video_id)
      expect(youtube_ids).not_to include(other_video.youtube_video_id)
    end

    # Phase 7 Path A2 — Video JSON summary collapses around the
    # surviving columns: id, youtube_video_id, channel_id, channel_url,
    # star, last_synced_at, plus aggregate stats and `trend`. Title /
    # description / privacy_status / published_at / duration_seconds
    # are gone.
    it "returns the video summary shape pito-sh expects (Phase 12 expanded)" do
      get videos_channel_path(channel, format: :json)
      row = response.parsed_body.first
      expect(row).to include(
        "id", "youtube_video_id", "channel_id", "channel_url",
        "title", "privacy_status", "published_at",
        "star", "views", "likes", "comments", "watch_time_minutes",
        "last_synced_at", "imported", "trend"
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

    # Phase B revamp (2026-05-06) — multi-pane view emits N `.pane`
    # children inside a single `.pane-strip`. The global CSS handles A/B
    # alternation via `:nth-child(odd)`/`:nth-child(even)`; the view
    # itself stays markup-only — every pane carries `class="pane"` and
    # the browser paints them. Asserting via the marker count keeps the
    # test decoupled from per-pane decoration (arrows, headings).
    it "renders one .pane per channel inside a single .pane-strip" do
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      strips = response.body.scan(/class="pane-strip"/).size
      panes = response.body.scan(/class="pane(?:\s[^"]*)?"/).size
      expect(strips).to eq(1)
      expect(panes).to eq(2)
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
    # Post URL-paste drop, channels enter the system through the
    # /settings/youtube multi-select flow OR via direct Channel.create
    # in services / MCP. The model callback that enqueues ChannelSync
    # on create still fires whichever way the row is born; this spec
    # exercises that boundary at the model layer (no HTTP).
    it "Channel.create enqueues exactly one ChannelSync" do
      ChannelSync.clear
      Channel.create!(channel_url: valid_url)
      expect(ChannelSync.jobs.size).to eq(1)
      expect(ChannelSync.jobs.first["args"].first).to eq(Channel.last.id)
    end
  end
end
