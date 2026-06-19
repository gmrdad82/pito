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
end
