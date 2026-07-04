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

      it "has exactly one rule whose patterns match all paths" do
        rule = response.parsed_body["rules"].first
        expect(rule["patterns"]).to eq([ ".*" ])
      end

      it "sets uri to the Hotwire web fragment on the rule properties" do
        props = response.parsed_body["rules"].first["properties"]
        expect(props["uri"]).to eq("hotwire://fragment/web")
      end

      it "sets context to 'default' on the rule properties" do
        props = response.parsed_body["rules"].first["properties"]
        expect(props["context"]).to eq("default")
      end

      it "enables pull_to_refresh on the rule properties" do
        props = response.parsed_body["rules"].first["properties"]
        expect(props["pull_to_refresh_enabled"]).to be true
      end
    end
  end
end
