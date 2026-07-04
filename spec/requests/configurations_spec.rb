# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Configurations requests", type: :request do
  describe "GET /configurations/android_v1.json" do
    context "without a session (anonymous)" do
      before { get "/configurations/android_v1.json" }

      it "responds with 200 OK — not a redirect to auth" do
        expect(response).to have_http_status(:ok)
      end

      it "returns JSON content type" do
        expect(response.content_type).to match(%r{application/json})
      end

      it "includes a top-level 'settings' key that is an empty object" do
        body = response.parsed_body
        expect(body["settings"]).to eq({})
      end

      it "includes a top-level 'rules' key that is an array" do
        body = response.parsed_body
        expect(body["rules"]).to be_an(Array)
      end

      it "leads with the catch-all rule matching every path" do
        rule = response.parsed_body["rules"].first
        expect(rule["patterns"]).to eq([ ".*" ])
      end

      it "sets uri to the Hotwire web fragment on the catch-all properties" do
        props = response.parsed_body["rules"].first["properties"]
        expect(props["uri"]).to eq("hotwire://fragment/web")
      end

      it "sets the fallback_uri to the same web fragment" do
        props = response.parsed_body["rules"].first["properties"]
        expect(props["fallback_uri"]).to eq("hotwire://fragment/web")
      end

      it "sets context to 'default' on the catch-all properties" do
        props = response.parsed_body["rules"].first["properties"]
        expect(props["context"]).to eq("default")
      end

      # The scrollback is a live cable stream; the pull gesture fights
      # scrolling. Mirrors the shell's bundled config (pito-android v1.0.0).
      it "disables pull_to_refresh on the catch-all properties" do
        props = response.parsed_body["rules"].first["properties"]
        expect(props["pull_to_refresh_enabled"]).to be false
      end

      it "clears the back stack on the root patterns via the second rule" do
        rule = response.parsed_body["rules"].second
        expect(rule["patterns"]).to eq([ "^$", "^/$" ])
        expect(rule["properties"]).to eq({ "presentation" => "clear_all" })
      end

      it "is publicly cacheable for an hour so launches stay fast" do
        expect(response.headers["Cache-Control"]).to include("public")
        expect(response.headers["Cache-Control"]).to include("max-age=3600")
      end
    end
  end
end
