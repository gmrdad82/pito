require "rails_helper"

# Layout integration for the unified leader-menu schema. The
# `<script type="application/json" id="pito-keybindings">` tag is
# the wire between the Ruby loader and the Stimulus
# `leader-menu_controller.js`; the controller parses it on `connect`
# and walks the menu tree in response to SPACE / Esc / Backspace /
# key presses. Source-of-truth doc:
#   docs/notes/2026-05-10-23-30-00-keybindings-unified-schema-proposal.md
#   (with the locked-decision block dated 2026-05-11 at the bottom).
RSpec.describe "Leader menu layout integration", type: :request do
  %w[/ /channels /videos /settings].each do |path|
    it "GET #{path} mounts data-controller leader-menu on <body>" do
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(
        /<body[^>]*data-controller="[^"]*\bleader-menu\b[^"]*"/
      )
    end

    it "GET #{path} renders the <script id=pito-keybindings> tag" do
      get path
      expect(response.body).to include('<script type="application/json" id="pito-keybindings">')
    end

    it "GET #{path} embeds a JSON payload with the leader + menus keys" do
      get path
      match = response.body.match(
        %r{<script type="application/json" id="pito-keybindings">(?<json>.*?)</script>}m
      )
      expect(match).not_to be_nil, "expected to find the keybindings <script> tag"
      payload = JSON.parse(match[:json])
      expect(payload).to include("leader", "menus")
      expect(payload.fetch("menus")).to include("root", "channels", "videos", "list_ops")
    end

    it "GET #{path} renders the popup placeholder div" do
      get path
      expect(response.body).to include('id="leader-menu-popup"')
      expect(response.body).to include('data-leader-menu-target="popup"')
    end

    it "GET #{path} renders the [_] footer link wired to leader-menu#openRoot" do
      get path
      # ERB encodes `->` as `-&gt;` inside attribute values; match the
      # encoded bytes so the assertion is grounded in real output.
      expect(response.body).to include("click-&gt;leader-menu#openRoot")
      expect(response.body).to match(/\[<span class="bl">_<\/span>\]/)
    end
  end

  describe "auth-chrome-hidden pages" do
    it "does NOT render the [_] footer link on /login (content_for :hide_chrome)" do
      get "/login"
      expect(response).to have_http_status(:ok)
      # The footer nav (which carries the [_] link) is gated by
      # `unless content_for?(:hide_chrome)`; auth pages set that flag.
      expect(response.body).not_to include("click-&gt;leader-menu#openRoot")
    end

    it "still embeds the schema script tag even on chrome-hidden pages" do
      # The schema is harmless on chrome-hidden pages; keeping it
      # rendered means the Stimulus controller can no-op gracefully
      # (popup target missing) without complicated conditionals.
      get "/login"
      expect(response.body).to include('id="pito-keybindings"')
    end
  end

  describe "schema payload locked shape" do
    before { get "/" }

    def payload
      match = response.body.match(
        %r{<script type="application/json" id="pito-keybindings">(?<json>.*?)</script>}m
      )
      JSON.parse(match[:json])
    end

    it "exposes the SPACE leader with the underscore display glyph" do
      leader = payload.fetch("leader")
      expect(leader.fetch("key")).to eq(" ")
      expect(leader.fetch("display")).to eq("_")
    end

    it "filters the TUI-only [q] item out of the root menu" do
      root_items = payload.fetch("menus").fetch("root").fetch("items")
      expect(root_items.map { |i| i.fetch("key") }).not_to include("q")
    end
  end
end
