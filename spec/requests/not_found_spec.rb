# frozen_string_literal: true

require "rails_helper"

# Dynamic 404 page.
#
# The test environment sets `config.consider_all_requests_local = true` and
# `config.action_dispatch.show_exceptions = :rescuable`, which means routing
# errors for truly unknown paths surface as raw exceptions in test rather than
# going through exceptions_app. To reliably exercise the dynamic 404 action we
# use two complementary strategies:
#
#  1. Direct route hit — GET /404 reaches start_screens#not_found directly
#     (this route always exists regardless of exceptions_app routing). This is
#     the canonical assertion that the action renders the suggestions chatbox
#     with status 404.
#
#  2. Catch-all route — GET /some-unknown-path is matched by the wildcard
#     `match "*path"` route appended at the end of routes.rb, so it also
#     reaches the not_found action without raising a routing error.
#
# Both routes are exercised without needing to override env_config.

RSpec.describe "Dynamic 404 page", type: :request do
  describe "GET /404 (exceptions_app primary route)" do
    before { get "/404" }

    it "responds with 404 status" do
      expect(response).to have_http_status(:not_found)
    end

    it "renders the suggestions chatbox (catalog script tag)" do
      expect(response.body).to include('data-pito--suggestions-target="catalog"')
    end

    it "renders the autosuggest palette div" do
      expect(response.body).to include("pito-suggestions-palette")
    end

    it "renders the chatbox wrapper" do
      expect(response.body).to include("pito-chatbox")
    end
  end

  describe "GET /<unknown-path> (catch-all route)" do
    before { get "/this-does-not-exist-#{SecureRandom.hex(4)}" }

    it "responds with 404 status" do
      expect(response).to have_http_status(:not_found)
    end

    it "renders the suggestions chatbox (catalog script tag)" do
      expect(response.body).to include('data-pito--suggestions-target="catalog"')
    end
  end

  describe "known routes are not shadowed by the catch-all" do
    it "GET / still returns 200" do
      get "/"
      expect(response).to have_http_status(:ok)
    end

    it "POST /suggestions still returns a response (not 404)" do
      post "/suggestions", params: { input: "/help" }
      expect(response.status).not_to eq(404)
    end
  end

  # ── SHOWCASE-START-NOTFOUND: auth-gated hints on 404 page ─────────────────────
  # Authenticated visitors get command hints (seed suggestions JSON in the script
  # tag, rotated through the native placeholder by pito--placeholder-rotate);
  # unauthenticated visitors get an empty set and the login-hint placeholder.

  describe "GET /404 showcase auth gating" do
    context "unauthenticated" do
      before { get "/404" }

      it "renders an empty hints JSON array (no rotation for unauthenticated)" do
        script_pattern = /<script[^>]+id="pito-showcase-data"[^>]*>\s*\[\s*\]/
        expect(response.body).to match(script_pattern)
      end
    end

    context "authenticated" do
      before do
        seed = ROTP::Base32.random_base32
        AppSetting.enroll_totp!(seed: seed)
        post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
        get "/404"
      end

      it "renders non-empty hints JSON (placeholder-rotate cycles for authenticated)" do
        # The hints data script must contain at least one suggestion string.
        # The seed set always includes "list games" so we can assert on that.
        expect(response.body).to include('"list games"')
        # And the script tag itself must be present (wired by the chatbox).
        expect(response.body).to include('id="pito-showcase-data"')
      end

      it "renders the chatbox with a non-login native placeholder (authenticated hint)" do
        # The placeholder is always a real sampled hint; authenticated visitors get
        # an authenticated hint, never the "/login" hint.
        expect(response.body).not_to match(/placeholder="[^"]+\/login/)
      end
    end
  end
  describe "the Hotwire Native shell (owner ruling 2026-07-13, design A)" do
    # The native WebView never renders an HTTP error body — a deleted
    # conversation's URL trapped the app on the library's dead error screen.
    # The SAME graceful page ships as 200 to the app so it renders like any
    # visit; browsers keep the honest 404.
    let(:native_ua) { "PITO; v1.2.0; Hotwire Native Android; Turbo Native Android" }

    it "serves the graceful not_found page with 200 to the app" do
      get "/unknown-void", headers: { "User-Agent" => native_ua }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("404")
    end

    it "keeps the honest 404 for browsers" do
      get "/unknown-void", headers: { "User-Agent" => "Mozilla/5.0" }
      expect(response).to have_http_status(:not_found)
    end
  end
end
