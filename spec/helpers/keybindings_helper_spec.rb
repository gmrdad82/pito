require "rails_helper"

# Helper that exposes `config/keybindings.yml` (the unified
# keybindings schema — single source of truth for the Rails web
# leader-menu popup AND the Rust `pito` CLI's Ratatui overlay) to
# the layout. The schema is loaded into
# `Rails.application.config.keybindings` at boot by
# `config/initializers/keybindings.rb`; the helper filters for the
# requested surface and serializes it for embed in the layout's
# `<script type="application/json" id="pito-keybindings">` tag.
#
# 2026-05-18 — the leader menu is now a flat 2-key dispatch (no
# nested submenus). The earlier per-resource submenu blocks
# (`channels`, `videos`, `projects`, `games`, `notifications`,
# `calendar`) were folded into the root menu as multi-char keys
# (`Cl`, `Vl`, `Pl`, `Gl`, `Nl`, `cs`, …). Only `root` survives in
# the `menus:` block.
RSpec.describe KeybindingsHelper, type: :helper do
  describe ".keybindings_for_surface" do
    it "returns a hash with the leader + menus + page_actions + modal_actions keys" do
      schema = helper.keybindings_for_surface(:web)
      expect(schema).to be_a(Hash)
      expect(schema).to include("leader", "menus", "page_actions", "modal_actions")
    end

    it "exposes the SPACE leader with the underscore display glyph" do
      leader = helper.keybindings_for_surface(:web).fetch("leader")
      expect(leader.fetch("key")).to eq(" ")
      expect(leader.fetch("display")).to eq("_")
    end

    it "ships a single `root` menu (flat 2-key dispatch — no submenus)" do
      menus = helper.keybindings_for_surface(:web).fetch("menus")
      expect(menus.keys).to eq([ "root" ])
    end

    describe "root menu — direct single-key entries" do
      let(:items) do
        helper.keybindings_for_surface(:web)
              .fetch("menus").fetch("root").fetch("items")
      end

      it "exposes [h] home with a direct navigate action" do
        row = items.find { |i| i["key"] == "h" }
        expect(row).not_to be_nil
        expect(row.fetch("label")).to eq("home")
        expect(row.fetch("action")).to eq("type" => "navigate", "path" => "/")
        expect(row).not_to have_key("submenu")
      end

      it "exposes [S] settings with a direct navigate action" do
        row = items.find { |i| i["key"] == "S" }
        expect(row).not_to be_nil
        expect(row.fetch("label")).to eq("settings")
        expect(row.fetch("action")).to eq("type" => "navigate", "path" => "/settings")
        expect(row).not_to have_key("submenu")
      end

      it "exposes [Q] logout with the logout action" do
        row = items.find { |i| i["key"] == "Q" }
        expect(row).not_to be_nil
        expect(row.fetch("label")).to eq("logout")
        expect(row.fetch("action")).to eq("type" => "logout")
      end
    end

    describe "root menu — flat 2-key bindings (folded submenus)" do
      # Each formerly-nested submenu collapses to multi-char keys under
      # a unique prefix letter. The prefix accumulator
      # (`leader_menu_controller.js#handlePrefixKey`) resolves the
      # second key the same way it does for `page_actions` 2-key
      # bindings (`fr`/`fs`/`fo` on /games, `sr`/`vr` on /settings).
      let(:items) do
        helper.keybindings_for_surface(:web)
              .fetch("menus").fetch("root").fetch("items")
      end

      flat_bindings = {
        # Calendar — lowercase `c` prefix.
        "cs"  => { label: "calendar schedule",           action: { "type" => "navigate", "path" => "/calendar/schedule" } },
        "cm"  => { label: "calendar month",              action: { "type" => "navigate", "path" => "/calendar/month" } },
        "ct"  => { label: "calendar today",              action: { "type" => "today" } },
        "c+"  => { label: "calendar new",                action: { "type" => "open", "target" => "new_calendar_entry" } },
        # Channels — capital `C` prefix.
        "Cl"  => { label: "channels list",               action: { "type" => "navigate", "path" => "/channels" } },
        "C+"  => { label: "channels add",                action: { "type" => "navigate", "path" => "/channels" } },
        "C-"  => { label: "channels delete",             action: { "type" => "bulk_delete" } },
        "Cy"  => { label: "channels sync",               action: { "type" => "bulk_sync" } },
        # Videos — capital `V` prefix.
        "Vl"  => { label: "videos list",                 action: { "type" => "navigate", "path" => "/videos" } },
        "V+"  => { label: "videos upload",               action: { "type" => "open", "target" => "video_upload" } },
        "V-"  => { label: "videos delete",               action: { "type" => "bulk_delete" } },
        # Projects — capital `P` prefix.
        "Pl"  => { label: "projects list",               action: { "type" => "navigate", "path" => "/projects" } },
        "P+"  => { label: "projects new",                action: { "type" => "open", "target" => "new_project" } },
        "P-"  => { label: "projects delete",             action: { "type" => "bulk_delete" } },
        # Games — capital `G` prefix.
        "Gl"  => { label: "games list",                  action: { "type" => "navigate", "path" => "/games" } },
        "G+"  => { label: "games new",                   action: { "type" => "open", "target" => "igdb_search" } },
        # Notifications — capital `N` prefix.
        "Nl"  => { label: "notifications list",          action: { "type" => "open", "target" => "notifications_modal" } },
        "Nu"  => { label: "notifications filter unread", action: { "type" => "filter_unread" } },
        "Nm"  => { label: "notifications mark all read", action: { "type" => "mark_all_read" } }
      }.freeze

      flat_bindings.each do |key, expected|
        it "ships the [#{key}] #{expected[:label]} binding" do
          row = items.find { |i| i["key"] == key }
          expect(row).not_to be_nil, "expected a flat binding for #{key.inspect}"
          expect(row.fetch("label")).to eq(expected[:label])
          expect(row.fetch("action")).to eq(expected[:action])
          expect(row).not_to have_key("submenu")
        end
      end

      it "no root row carries a `submenu` field" do
        offenders = items.select { |i| i.is_a?(Hash) && i.key?("submenu") }
        expect(offenders).to be_empty,
          "expected no rows with `submenu`, found #{offenders.inspect}"
      end

      it "every binding key in the root menu is unique" do
        keys = items.reject { |i| i["divider"] }.map { |i| i["key"] }
        expect(keys.uniq.length).to eq(keys.length),
          "expected every binding key to be unique, got duplicates in #{keys.inspect}"
      end
    end

    describe "surface filtering" do
      it "filters TUI-only [q] quit out of the :web payload" do
        items = helper.keybindings_for_surface(:web)
                      .fetch("menus").fetch("root").fetch("items")
        keys = items.reject { |i| i["divider"] }.map { |i| i["key"] }
        expect(keys).not_to include("q")
      end

      it "keeps TUI-only [q] quit on the :tui payload" do
        items = helper.keybindings_for_surface(:tui)
                      .fetch("menus").fetch("root").fetch("items")
        keys = items.reject { |i| i["divider"] }.map { |i| i["key"] }
        expect(keys).to include("q")
      end
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
