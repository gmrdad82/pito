require "rails_helper"

# Phase 16 §3 — Notification controller request matrix.
RSpec.describe "Notifications", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:unread_a) do
    travel_to(2.hours.ago) do
      create(:notification, :video_published)
    end
  end
  let!(:unread_b) do
    travel_to(1.hour.ago) do
      create(:notification, :sync_error)
    end
  end
  let!(:read_a) do
    travel_to(3.hours.ago) do
      create(:notification, :read, :calendar_entry_firing)
    end
  end

  describe "GET /notifications" do
    it "returns 200 (happy)" do
      get "/notifications"
      expect(response).to have_http_status(:ok)
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get "/notifications"
      expect(response).to redirect_to(login_path)
    end

    it "renders all rows by default" do
      get "/notifications"
      # Each row's title is rendered via NotificationFormatter::InApp,
      # which calls the per-kind template's `#title` (NOT the
      # `notifications.title` column). Assert on the dom_ids — every
      # row partial wraps in `id="notification_<id>"`.
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(unread_a))
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(unread_b))
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(read_a))
    end

    it "filter=unread returns only unread rows" do
      get "/notifications?filter=unread"
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(unread_a))
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(unread_b))
      expect(response.body).not_to include(ActionView::RecordIdentifier.dom_id(read_a))
    end

    it "filter=all returns all rows" do
      get "/notifications?filter=all"
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(read_a))
    end

    it "kind=sync_error filters by kind" do
      get "/notifications?kind=sync_error"
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(unread_b))
      expect(response.body).not_to include(ActionView::RecordIdentifier.dom_id(unread_a))
    end

    it "kind=invalid is silently ignored (degrades to all)" do
      get "/notifications?kind=__nope__"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(unread_a))
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(unread_b))
    end

    it "severity=urgent filters by severity" do
      get "/notifications?severity=urgent"
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(unread_b)) # urgent
      expect(response.body).not_to include(ActionView::RecordIdentifier.dom_id(unread_a)) # info
    end

    it "page=2 paginates (50 per page)" do
      get "/notifications?page=2"
      expect(response).to have_http_status(:ok)
    end

    it "renders the unread badge in nav" do
      get "/notifications"
      # 2 unread (unread_a, unread_b). UX restructure 2026-05-10 — the
      # badge is now a `<sup class="notifications-badge-count">N</sup>`
      # next to `[notifications]`, no surrounding brackets.
      expect(response.body).to match(/<sup[^>]*notifications-badge-count[^>]*>\s*2\s*<\/sup>/)
    end

    it "shows the empty-state copy when there are no rows" do
      Notification.delete_all
      get "/notifications"
      expect(response.body).to include("no notifications yet.")
    end

    # 2026-05-10 — checkbox-always-visible refinement. The per-row
    # checkbox no longer hides on read rows; the column stays stable
    # across the table. The dynamic `[ mark N as read ]` controller
    # filters by `.notification-unread` when counting, so a ticked
    # box on a read row is silently ignored (no functional regression).
    describe "row checkbox column is always-on" do
      it "renders a checkbox on every unread row" do
        get "/notifications"
        unread_count_in_body = response.body.scan(
          %r{<tr[^>]*notification-unread[\s\S]*?</tr>}
        ).count { |row| row.match?(/data-bulk-select-target="checkbox"/) }
        expect(unread_count_in_body).to eq(2)
      end

      it "renders a checkbox on read rows too (always-on column)" do
        get "/notifications?filter=all"
        read_row_html = response.body[
          /<tr[^>]*id="#{ActionView::RecordIdentifier.dom_id(read_a)}"[\s\S]*?<\/tr>/
        ]
        expect(read_row_html).to be_present
        expect(read_row_html).to match(/data-bulk-select-target="checkbox"/)
      end
    end

    # 2026-05-10 — glyph legend, repositioned 2026-05-11 to the
    # BOTTOM of the page and rendered as a two-column grid (one
    # `<emoji> <kind label>` pair per line). One legend line per
    # registered event-type emoji, sourced from
    # `NotificationFormatter::EVENT_TYPE_EMOJI`. The legend stays in
    # sync with the formatter constant — no separate copy to maintain.
    describe "glyph legend" do
      it "renders the legend wrapper with the documented class" do
        get "/notifications"
        expect(response.body).to include("notification-glyph-legend")
      end

      it "renders every emoji from EVENT_TYPE_EMOJI in the legend" do
        get "/notifications"
        NotificationFormatter::EVENT_TYPE_EMOJI.each_value do |emoji|
          expect(response.body).to include(emoji)
        end
      end

      it "renders a humanized kind label for each emoji" do
        get "/notifications"
        NotificationFormatter::EVENT_TYPE_EMOJI.each_key do |kind|
          expect(response.body).to include(kind.tr("_", " "))
        end
      end

      it "renders the legend inside the modal-mode frame too" do
        get "/notifications?modal=yes"
        # The legend lives inside the modal wrapper (`<turbo-frame
        # id="notifications_modal_frame">`) so the modal surface
        # carries it as well — both surfaces share the index template.
        expect(response.body).to include("notification-glyph-legend")
      end

      # 2026-05-11 — repositioned. The legend used to render BEFORE
      # the table as a single muted caption; per user direction it
      # now renders AFTER the table so the table is the first thing
      # you read, and the legend decodes the icons in retrospect.
      it "renders the legend AFTER the table (below it in document order)" do
        get "/notifications"
        body = response.body
        table_close_pos = body.index("</table>")
        legend_pos      = body.index("notification-glyph-legend")
        expect(table_close_pos).not_to be_nil
        expect(legend_pos).not_to be_nil
        expect(table_close_pos).to be < legend_pos
      end

      # 2026-05-11 — two-column layout. One item per line, two
      # columns side-by-side, implemented as a CSS grid with two
      # equal tracks.
      it "lays the legend out as a two-column grid" do
        get "/notifications"
        legend_html = response.body[
          %r{<div[^>]*notification-glyph-legend[^>]*>[\s\S]*?</div>}
        ]
        expect(legend_html).to be_present
        # CSS `grid-template-columns: 1fr 1fr` declares the two-track
        # grid; assert on the substring so a future CSS hoist to a
        # class still leaves the intent visible in the markup.
        expect(legend_html).to match(/display:\s*grid/)
        expect(legend_html).to match(/grid-template-columns:\s*1fr\s+1fr/)
      end

      # 2026-05-11 — one item per line. Each legend pair lives in
      # its own `.notification-glyph-legend-item` block-level div, so
      # the grid stacks pairs vertically within each column.
      it "wraps each pair in its own block-level item element" do
        get "/notifications"
        item_count = response.body.scan(
          /class="notification-glyph-legend-item"/
        ).length
        expect(item_count).to eq(NotificationFormatter::EVENT_TYPE_EMOJI.length)
      end
    end

    # 2026-05-11 — explicit `<thead>` row labels per user direction.
    # Five columns: select, kind, title, severity, when. Matches the
    # app-wide `<thead><th>…</th></thead>` table-header pattern.
    describe "table header row" do
      it "renders the explicit <thead> with five labelled columns" do
        get "/notifications"
        thead_html = response.body[%r{<thead>[\s\S]*?</thead>}]
        expect(thead_html).to be_present
        %w[select kind title severity when].each do |label|
          expect(thead_html).to match(/<th[^>]*>\s*#{label}\s*</)
        end
      end

      it "does not render <thead> when the empty state shows (no table)" do
        Notification.delete_all
        get "/notifications"
        expect(response.body).not_to include("<thead>")
        expect(response.body).to include("no notifications yet.")
      end

      it "renders <thead> inside modal-mode frame too" do
        get "/notifications?modal=yes"
        expect(response.body).to include("<thead>")
      end
    end
  end

  # Layout-level notifications modal (2026-05-10). `?modal=yes` or a
  # request whose `Turbo-Frame` header matches the modal frame id flips
  # the index into a layout-less, frame-wrapped response. The standalone
  # `/notifications` page MUST keep its previous shape (every spec
  # above this block asserts against the un-flipped DOM, which is the
  # primary regression guard).
  describe "GET /notifications?modal=yes (layout-level modal mode)" do
    it "returns 200" do
      get "/notifications?modal=yes"
      expect(response).to have_http_status(:ok)
    end

    it "omits the layout (no header / footer chrome)" do
      get "/notifications?modal=yes"
      # The layout renders the `<header>` chrome and the keyboard
      # shortcuts modal. Layout-less mode strips both.
      expect(response.body).not_to include("<header")
      expect(response.body).not_to include("keyboard-shortcuts-modal")
    end

    it "wraps the body in the matching Turbo Frame" do
      get "/notifications?modal=yes"
      # The index template emits a bare `<turbo-frame id="...">` open
      # tag when in modal mode, with the H1 sitting inside it. The
      # layout helper's empty frame (rendered into the standalone
      # page) uses a different attribute order (`loading="lazy" ...
      # id="..."`), so the bare-id substring is unique to modal mode.
      body = response.body
      frame_pos = body.index('<turbo-frame id="notifications_modal_frame"')
      h1_pos    = body.index("<h1>notifications</h1>")
      expect(frame_pos).not_to be_nil
      expect(h1_pos).not_to be_nil
      expect(frame_pos).to be < h1_pos
    end

    it "renders the heading + cleanup caption + filter chip inside the frame" do
      get "/notifications?modal=yes"
      expect(response.body).to include("<h1>notifications</h1>")
      expect(response.body).to include("notifications are deleted 7 days after being read.")
      expect(response.body).to match(/class="filter-chip"/)
    end

    it "renders the standard standalone page (with layout) when modal param is absent" do
      get "/notifications"
      expect(response.body).to include("<header")
      expect(response.body).not_to include('<turbo-frame id="notifications_modal_frame"')
    end

    it "ignores stray modal values (yes/no boundary)" do
      get "/notifications?modal=true" # NOT "yes" — must fall through.
      # The standalone page renders WITH the layout, which renders the
      # empty layout-level notifications-modal Turbo Frame too — so
      # the discriminator is the layout `<header>` chrome, not the
      # frame's presence.
      expect(response.body).to include("<header")
    end

    it "treats a matching Turbo-Frame request header as modal context" do
      get "/notifications", headers: { "Turbo-Frame" => "notifications_modal_frame" }
      expect(response.body).to include('<turbo-frame id="notifications_modal_frame"')
      expect(response.body).not_to include("<header")
    end

    it "ignores a non-matching Turbo-Frame header" do
      # A non-matching `Turbo-Frame` header does NOT flip the index into
      # modal-mode — the controller renders WITH the layout. (Turbo
      # itself may post-process the response to extract only the
      # requested frame, but that's its concern; the server-rendered
      # body wraps the content in the standard layout, NOT in the
      # notifications-modal Turbo Frame.)
      get "/notifications", headers: { "Turbo-Frame" => "some_other_frame" }
      expect(response.body).not_to include('<turbo-frame id="notifications_modal_frame">')
    end

    it "preserves filter / kind / severity inside modal mode" do
      get "/notifications?modal=yes&filter=unread"
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(unread_a))
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(unread_b))
      expect(response.body).not_to include(ActionView::RecordIdentifier.dom_id(read_a))
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get "/notifications?modal=yes"
      expect(response).to redirect_to(login_path)
    end
  end

  describe "GET /notifications/:id" do
    it "returns 200 for a valid id (happy)" do
      get "/notifications/#{unread_a.id}"
      expect(response).to have_http_status(:ok)
    end

    it "404s for an unknown id" do
      get "/notifications/999999"
      expect(response).to have_http_status(:not_found)
    end

    it "renders the formatter-derived title" do
      payload = NotificationFormatter::InApp.payload_for(unread_a)
      get "/notifications/#{unread_a.id}"
      expect(response.body).to include(payload[:title])
    end

    it "renders the back link" do
      get "/notifications/#{unread_a.id}"
      expect(response.body).to match(/\[<span class="bl">back<\/span>\]/)
    end

    it "renders [ mark read ] when unread" do
      get "/notifications/#{unread_a.id}"
      expect(response.body).to include("mark read")
    end

    it "renders [ mark unread ] when read" do
      get "/notifications/#{read_a.id}"
      expect(response.body).to include("mark unread")
    end

    it "renders per-channel delivery state" do
      get "/notifications/#{unread_a.id}"
      expect(response.body).to include("in_app: yes")
      expect(response.body).to match(/discord:\s+(pending|disabled|\d{4}-\d{2}-\d{2})/)
      expect(response.body).to match(/slack:\s+(pending|disabled|\d{4}-\d{2}-\d{2})/)
    end

    it "shows last_error when non-blank" do
      unread_a.update!(last_error: "boom: HTTP 502")
      get "/notifications/#{unread_a.id}"
      expect(response.body).to include("boom: HTTP 502")
    end

    it "omits the [ open ] link when url is blank" do
      unread_a.update!(url: nil)
      get "/notifications/#{unread_a.id}"
      expect(response.body).not_to match(/\[<span class="bl">open<\/span>\]/)
    end

    it "renders the [ open ] link when url is present" do
      unread_a.update!(url: "https://example.com/x")
      get "/notifications/#{unread_a.id}"
      expect(response.body).to match(/\[<span class="bl">open<\/span>\]/)
    end

    it "does NOT include `data-turbo-confirm` anywhere on the detail page" do
      get "/notifications/#{unread_a.id}"
      expect(response.body).not_to include("data-turbo-confirm")
    end

    it "does NOT include `confirm()` JS calls in the rendered HTML" do
      get "/notifications/#{unread_a.id}"
      expect(response.body).not_to include("window.confirm")
      expect(response.body).not_to match(/onclick=.*confirm\(/)
    end
  end

  describe "PATCH /notifications/:id/read" do
    it "stamps in_app_read_at (happy)" do
      expect {
        patch "/notifications/#{unread_a.id}/read"
      }.to change { unread_a.reload.in_app_read_at }.from(nil)
    end

    it "is idempotent on an already-read row" do
      stamp = read_a.in_app_read_at
      expect {
        patch "/notifications/#{read_a.id}/read"
      }.not_to change { read_a.reload.in_app_read_at }
      # No new stamp because the controller short-circuits when read?.
      expect(read_a.reload.in_app_read_at).to be_within(1.second).of(stamp)
    end

    it "responds with redirect on HTML" do
      patch "/notifications/#{unread_a.id}/read"
      expect(response).to redirect_to(notifications_path).or have_http_status(:redirect)
    end

    it "responds with turbo_stream on Turbo Stream Accept" do
      patch "/notifications/#{unread_a.id}/read",
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to include("turbo-stream")
    end

    it "ignores a smuggled in_app_read_at param" do
      future = 100.years.from_now
      patch "/notifications/#{unread_a.id}/read",
            params: { in_app_read_at: future.iso8601 }
      stamped = unread_a.reload.in_app_read_at
      expect(stamped).to be_present
      # Controller stamps Time.current; smuggled value must be ignored.
      expect(stamped).to be < 1.minute.from_now
    end
  end

  describe "PATCH /notifications/:id/unread" do
    it "clears in_app_read_at (happy)" do
      expect {
        patch "/notifications/#{read_a.id}/unread"
      }.to change { read_a.reload.in_app_read_at }.to(nil)
    end

    it "is a no-op on already-unread row" do
      expect {
        patch "/notifications/#{unread_a.id}/unread"
      }.not_to change { unread_a.reload.in_app_read_at }
    end
  end

  describe "PATCH /notifications/mark_read (collection bulk)" do
    it "updates the supplied ids (happy)" do
      patch "/notifications/mark_read", params: { ids: "#{unread_a.id},#{unread_b.id}" }
      expect(unread_a.reload.in_app_read_at).to be_present
      expect(unread_b.reload.in_app_read_at).to be_present
    end

    it "ignores stray (unknown) ids and updates valid ones" do
      patch "/notifications/mark_read", params: { ids: "#{unread_a.id},999999" }
      expect(unread_a.reload.in_app_read_at).to be_present
    end

    it "redirects with alert when no ids provided" do
      patch "/notifications/mark_read", params: { ids: "" }
      expect(response).to redirect_to(notifications_path)
    end

    it "accepts array form ids[]=A&ids[]=B" do
      patch "/notifications/mark_read", params: { ids: [ unread_a.id.to_s, unread_b.id.to_s ] }
      expect(unread_a.reload.in_app_read_at).to be_present
      expect(unread_b.reload.in_app_read_at).to be_present
    end
  end

  describe "PATCH /notifications/mark_all_read" do
    it "updates every unread row" do
      expect(Notification.unread.count).to eq(2)
      patch "/notifications/mark_all_read"
      expect(Notification.unread.count).to eq(0)
    end

    it "is idempotent when there are no unread rows" do
      Notification.unread.update_all(in_app_read_at: Time.current)
      expect {
        patch "/notifications/mark_all_read"
      }.not_to change { Notification.unread.count }
    end
  end

  # Phase 16 §3 security fix-forward (F3 — 2026-05-10 audit). 5-second
  # per-user lock on `PATCH /notifications/mark_read` and
  # `PATCH /notifications/mark_all_read`. Mirrors Phase 13's
  # `analytics_refresh` cache-lock pattern.
  describe "F3 — rate-limit cache lock on bulk mark-read endpoints" do
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(memory_cache)
      # The Phase 12 `sign_in_as` helper in `spec/support/auth.rb`
      # auto-signs the request before each example; `User.first` is
      # the same auto-minted user for the duration of the spec so the
      # lock key resolves identically across both requests below.
    end

    describe "PATCH /notifications/mark_read" do
      it "writes a 5-second per-user lock on the first request (HTML)" do
        patch "/notifications/mark_read", params: { ids: "#{unread_a.id}" }
        user_id = User.first.id
        expect(memory_cache.exist?("notifications:mark_read:user:#{user_id}")).to be(true)
      end

      it "succeeds when the lock is free (HTML, happy)" do
        patch "/notifications/mark_read", params: { ids: "#{unread_a.id}" }
        expect(response).to redirect_to(notifications_path)
        expect(unread_a.reload.in_app_read_at).to be_present
      end

      it "redirects with an alert when the lock is held (HTML)" do
        user_id = User.first.id
        memory_cache.write("notifications:mark_read:user:#{user_id}", 1,
                           expires_in: 5.seconds)

        patch "/notifications/mark_read", params: { ids: "#{unread_a.id}" }
        expect(response).to redirect_to(notifications_path)
        follow_redirect!
        expect(flash[:alert] || response.body).to match(/slow down|rate.?limit/i)
      end

      it "does NOT update rows when the lock is held (HTML)" do
        user_id = User.first.id
        memory_cache.write("notifications:mark_read:user:#{user_id}", 1,
                           expires_in: 5.seconds)

        expect {
          patch "/notifications/mark_read", params: { ids: "#{unread_a.id}" }
        }.not_to change { unread_a.reload.in_app_read_at }
      end

      it "returns 429 + rate_limited JSON envelope when the lock is held (JSON)" do
        user_id = User.first.id
        memory_cache.write("notifications:mark_read:user:#{user_id}", 1,
                           expires_in: 5.seconds)

        patch "/notifications/mark_read",
              params: { ids: "#{unread_a.id}" },
              headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:too_many_requests)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("rate_limited")
        expect(body["retry_after_seconds"]).to eq(5)
      end

      it "succeeds after the lock expires (HTML)" do
        user_id = User.first.id
        lock_key = "notifications:mark_read:user:#{user_id}"
        memory_cache.write(lock_key, 1, expires_in: 5.seconds)
        memory_cache.delete(lock_key)

        patch "/notifications/mark_read", params: { ids: "#{unread_a.id}" }
        expect(response).to redirect_to(notifications_path)
        expect(unread_a.reload.in_app_read_at).to be_present
      end
    end

    describe "PATCH /notifications/mark_all_read" do
      it "writes a 5-second per-user lock on the first request (HTML)" do
        patch "/notifications/mark_all_read"
        user_id = User.first.id
        expect(memory_cache.exist?("notifications:mark_read:user:#{user_id}")).to be(true)
      end

      it "succeeds when the lock is free (HTML, happy)" do
        expect(Notification.unread.count).to eq(2)
        patch "/notifications/mark_all_read"
        expect(response).to redirect_to(notifications_path)
        expect(Notification.unread.count).to eq(0)
      end

      it "redirects with an alert when the lock is held (HTML)" do
        user_id = User.first.id
        memory_cache.write("notifications:mark_read:user:#{user_id}", 1,
                           expires_in: 5.seconds)

        patch "/notifications/mark_all_read"
        expect(response).to redirect_to(notifications_path)
        follow_redirect!
        expect(flash[:alert] || response.body).to match(/slow down|rate.?limit/i)
      end

      it "does NOT update rows when the lock is held (HTML)" do
        user_id = User.first.id
        memory_cache.write("notifications:mark_read:user:#{user_id}", 1,
                           expires_in: 5.seconds)

        expect {
          patch "/notifications/mark_all_read"
        }.not_to change { Notification.unread.count }
      end

      it "returns 429 + rate_limited JSON envelope when the lock is held (JSON)" do
        user_id = User.first.id
        memory_cache.write("notifications:mark_read:user:#{user_id}", 1,
                           expires_in: 5.seconds)

        patch "/notifications/mark_all_read",
              headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:too_many_requests)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("rate_limited")
        expect(body["retry_after_seconds"]).to eq(5)
      end

      it "succeeds after the lock expires (HTML)" do
        user_id = User.first.id
        lock_key = "notifications:mark_read:user:#{user_id}"
        memory_cache.write(lock_key, 1, expires_in: 5.seconds)
        memory_cache.delete(lock_key)

        patch "/notifications/mark_all_read"
        expect(response).to redirect_to(notifications_path)
        expect(Notification.unread.count).to eq(0)
      end

      it "shares the lock key with mark_read (both endpoints rate-limit together)" do
        # First call to mark_read writes the lock.
        patch "/notifications/mark_read", params: { ids: "#{unread_a.id}" }
        # Immediately follow with mark_all_read → blocked.
        patch "/notifications/mark_all_read",
              headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:too_many_requests)
      end
    end
  end

  describe "auth boundary" do
    it "GET /notifications redirects to login when unauthenticated", :unauthenticated do
      get "/notifications"
      expect(response).to redirect_to(login_path)
    end

    it "GET /notifications/:id redirects when unauthenticated", :unauthenticated do
      get "/notifications/#{unread_a.id}"
      expect(response).to redirect_to(login_path)
    end

    it "PATCH /notifications/:id/read redirects when unauthenticated", :unauthenticated do
      patch "/notifications/#{unread_a.id}/read"
      expect(response).to redirect_to(login_path)
    end

    it "PATCH /notifications/mark_read redirects when unauthenticated", :unauthenticated do
      patch "/notifications/mark_read", params: { ids: "#{unread_a.id}" }
      expect(response).to redirect_to(login_path)
    end

    it "PATCH /notifications/mark_all_read redirects when unauthenticated", :unauthenticated do
      patch "/notifications/mark_all_read"
      expect(response).to redirect_to(login_path)
    end
  end
end
