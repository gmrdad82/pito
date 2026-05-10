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
