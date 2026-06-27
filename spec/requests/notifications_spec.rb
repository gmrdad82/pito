# frozen_string_literal: true

require "rails_helper"

# GET /notifications — returns a Turbo Stream updating #pito-sidebar with the
# notifications list wrapped in the Sidebar shell.

RSpec.describe "GET /notifications", type: :request do
  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: Conversation.create!.uuid }
  end

  # ── Authenticated path ──────────────────────────────────────────────────────

  describe "when authenticated" do
    before { authenticate_via_totp }

    it "returns 200 OK" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
    end

    it "responds with turbo-stream content type" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.content_type).to include("text/vnd.turbo-stream.html")
    end

    it "targets pito-sidebar in the turbo stream" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include('target="pito-sidebar"')
    end

    it "renders the aside sidebar shell" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("<aside")
    end

    it "includes notification messages when notifications exist" do
      create(:notification, message: "Hello from test")
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("Hello from test")
    end

    it "renders the empty state when there are no notifications" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("No notifications")
    end

    it "renders unread notifications before read ones (panel_ordered)" do
      create(:notification, message: "I am read",   read_at: 1.hour.ago,  created_at: 2.hours.ago)
      create(:notification, message: "I am unread", read_at: nil,          created_at: 3.hours.ago)
      get notifications_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      unread_pos = response.body.index("I am unread")
      read_pos   = response.body.index("I am read")
      expect(unread_pos).to be < read_pos
    end

    it "renders the Notifications title" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("Notifications")
    end
  end

  # ── Pagination (keyset / infinite scroll) ────────────────────────────────────

  describe "pagination" do
    before { authenticate_via_totp }
    let(:ts) { { "Accept" => "text/vnd.turbo-stream.html" } }

    it "caps the first page at PAGE_SIZE rows" do
      create_list(:notification, Notification::PAGE_SIZE + 5)
      get notifications_path, headers: ts
      expect(response.body.scan('class="pito-notification-row').size).to eq(Notification::PAGE_SIZE)
    end

    it "renders a sentinel carrying the next-page URL when more rows exist" do
      create_list(:notification, Notification::PAGE_SIZE + 5)
      get notifications_path, headers: ts
      expect(response.body).to include('id="pito-list-pager-sentinel"')
      expect(response.body).to match(/data-pager-next-url="[^"]*\/notifications\?after=/)
    end

    it "shows the end-of-list sentinel (no next URL) when everything fits one page" do
      create_list(:notification, 3)
      get notifications_path, headers: ts
      expect(response.body).to include('id="pito-list-pager-sentinel"')
      expect(response.body).not_to include("data-pager-next-url")
    end

    it "APPENDS the next page and REPLACES the sentinel for a cursor request" do
      create_list(:notification, Notification::PAGE_SIZE + 3)
      _first, cursor = Notification.panel_page
      get notifications_path(after: cursor), headers: ts
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="pito-notifications-list"')
      expect(response.body).to include('action="replace"')
      expect(response.body).to include('target="pito-list-pager-sentinel"')
      # the tail page (3 rows) exhausts the list → sentinel has no next URL
      expect(response.body.scan('class="pito-notification-row').size).to eq(3)
      expect(response.body).not_to include("data-pager-next-url")
    end

    it "treats a garbage cursor as the first page (no crash)" do
      create_list(:notification, 2)
      get notifications_path(after: "@@@not-a-cursor@@@"), headers: ts
      expect(response).to have_http_status(:ok)
      expect(response.body.scan('class="pito-notification-row').size).to eq(2)
    end
  end

  # ── Unauthenticated path ────────────────────────────────────────────────────

  describe "when unauthenticated" do
    it "redirects to root (auth gate)" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to redirect_to(root_path)
    end

    it "does NOT return a Turbo Stream targeting pito-sidebar" do
      get notifications_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).not_to include('target="pito-sidebar"')
    end
  end
end
