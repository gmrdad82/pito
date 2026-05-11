require "rails_helper"

# Helper that exposes `config/keybindings.yml` (the unified
# keybindings schema — single source of truth for the Rails web
# leader-menu popup AND the Rust `pito` CLI's Ratatui overlay) to
# the layout. The schema is loaded into
# `Rails.application.config.keybindings` at boot by
# `config/initializers/keybindings.rb`; the helper filters for the
# requested surface and serializes it for embed in the layout's
# `<script type="application/json" id="pito-keybindings">` tag.
RSpec.describe KeybindingsHelper, type: :helper do
  describe ".keybindings_for_surface" do
    it "returns a hash with the leader + menus keys" do
      schema = helper.keybindings_for_surface(:web)
      expect(schema).to be_a(Hash)
      expect(schema).to include("leader", "menus")
    end

    it "exposes the SPACE leader with the underscore display glyph" do
      leader = helper.keybindings_for_surface(:web).fetch("leader")
      expect(leader.fetch("key")).to eq(" ")
      expect(leader.fetch("display")).to eq("_")
    end

    it "renders the canonical menu names (root + the locked submenus)" do
      menus = helper.keybindings_for_surface(:web).fetch("menus")
      expect(menus.keys).to include(
        "root", "calendar", "channels", "videos",
        "projects", "games", "bundles", "notifications",
        "search", "list_ops"
      )
    end

    it "exposes every root-menu binding from the locked schema" do
      root = helper.keybindings_for_surface(:web).fetch("menus").fetch("root")
      keys = root.fetch("items").map { |item| item.fetch("key") }
      # Excludes "q" — that one is TUI-only and gets filtered for :web.
      expect(keys).to match_array(%w[h c C V P G N S / | Q])
    end

    it "carries the navigate action with the path for the root [S]ettings item" do
      items = helper.keybindings_for_surface(:web)
                    .fetch("menus").fetch("root").fetch("items")
      settings = items.find { |i| i.fetch("key") == "S" }
      expect(settings.fetch("label")).to eq("settings")
      expect(settings.fetch("action")).to eq("type" => "navigate", "path" => "/settings")
    end

    it "tags the [c]alendar root item with a submenu reference" do
      items = helper.keybindings_for_surface(:web)
                    .fetch("menus").fetch("root").fetch("items")
      calendar = items.find { |i| i.fetch("key") == "c" }
      expect(calendar.fetch("submenu")).to eq("calendar")
    end

    it "filters TUI-only items off the :web surface" do
      web_root_keys = helper.keybindings_for_surface(:web)
                            .fetch("menus").fetch("root").fetch("items")
                            .map { |i| i.fetch("key") }
      expect(web_root_keys).not_to include("q")
    end

    it "keeps TUI-only items on the :tui surface" do
      tui_root_keys = helper.keybindings_for_surface(:tui)
                            .fetch("menus").fetch("root").fetch("items")
                            .map { |i| i.fetch("key") }
      expect(tui_root_keys).to include("q")
    end

    it "includes the [|] list-ops submenu with saved-views + contextual add" do
      list_ops = helper.keybindings_for_surface(:web)
                       .fetch("menus").fetch("list_ops")
      keys = list_ops.fetch("items").map { |i| i.fetch("key") }
      expect(keys).to include("l", "+")
    end

    it "wires the games [B] item to the bundles submenu" do
      games = helper.keybindings_for_surface(:web)
                    .fetch("menus").fetch("games").fetch("items")
      bundles_item = games.find { |i| i.fetch("key") == "B" }
      expect(bundles_item.fetch("submenu")).to eq("bundles")
    end
  end

  describe "#keybindings_as_json" do
    it "produces parseable JSON that round-trips to the same shape as the helper" do
      json = helper.keybindings_as_json
      parsed = JSON.parse(json.to_s)
      expect(parsed).to eq(helper.keybindings_for_surface(:web))
    end

    it "is marked html_safe so it can be embedded in a <script> tag" do
      expect(helper.keybindings_as_json).to be_html_safe
    end
  end
end
