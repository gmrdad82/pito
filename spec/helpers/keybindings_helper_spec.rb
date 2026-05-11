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

    describe "resource-row root items are submenu-only (2026-05-10 revert)" do
      # The schema revert: root-menu rows that point to a submenu DROP
      # the `action` field. Pressing C/V/P/G/c/N at the root drills
      # into the named submenu ONLY; the user must press `l` (list)
      # inside the submenu to actually navigate to /<resource>. The
      # previous combined `action + submenu` pattern proved
      # surprising (a single keystroke both navigated AND drilled) and
      # is gone. Lock the contract so a regression that re-introduces
      # the dual-action shape fails fast.
      ROOT_SUBMENU_ONLY_ROWS = {
        "c" => "calendar",
        "C" => "channels",
        "V" => "videos",
        "P" => "projects",
        "G" => "games",
        "N" => "notifications"
      }.freeze

      ROOT_SUBMENU_ONLY_ROWS.each do |key, expected_submenu|
        it "exposes submenu-only (no action) for the root [#{key}] row" do
          items = helper.keybindings_for_surface(:web)
                        .fetch("menus").fetch("root").fetch("items")
          row = items.find { |i| i.fetch("key") == key }
          expect(row).not_to be_nil, "expected root item with key #{key.inspect}"
          expect(row.fetch("submenu")).to eq(expected_submenu)
          expect(row).not_to have_key("action"),
            "expected root #{key.inspect} to drop the `action` field; got #{row.inspect}"
        end
      end

      it "keeps direct navigation on the root [h] home + [S] settings rows" do
        # h and S have no submenu, so they retain the navigate action.
        items = helper.keybindings_for_surface(:web)
                      .fetch("menus").fetch("root").fetch("items")
        home = items.find { |i| i.fetch("key") == "h" }
        settings = items.find { |i| i.fetch("key") == "S" }
        expect(home.fetch("action")).to eq("type" => "navigate", "path" => "/")
        expect(home).not_to have_key("submenu")
        expect(settings.fetch("action")).to eq("type" => "navigate", "path" => "/settings")
        expect(settings).not_to have_key("submenu")
      end
    end

    describe "label cleanup (bulk-toggle dropped, bulk-action labels renamed)" do
      # The `b` "bulk toggle (legacy)" entry was retired with the
      # selection-mode toggle; the bulk-action labels lost their
      # "bulk … (selection)" preamble so the rows read as plain verbs
      # (`delete`, `sync`, `resync`). Lock both the absence and the
      # rename across every menu that carries them.
      it "drops the [b] bulk-toggle (legacy) entry from the channels submenu" do
        channels = helper.keybindings_for_surface(:web)
                         .fetch("menus").fetch("channels").fetch("items")
        keys = channels.map { |i| i.fetch("key") }
        labels = channels.map { |i| i.fetch("label") }
        expect(keys).not_to include("b")
        expect(labels.join(" ")).not_to include("legacy")
      end

      it "drops [b] bulk-toggle (legacy) from every menu schema-wide" do
        menus = helper.keybindings_for_surface(:web).fetch("menus")
        menus.each do |name, menu|
          items = menu.fetch("items")
          b_items = items.select { |i| i.fetch("key") == "b" }
          expect(b_items).to be_empty,
            "expected no `b` item in #{name} submenu, found #{b_items.inspect}"
          legacy = items.select { |i| i.fetch("label", "").include?("legacy") }
          expect(legacy).to be_empty,
            "expected no 'legacy'-labeled items in #{name} submenu, found #{legacy.inspect}"
        end
      end

      it "renames channels bulk delete to plain 'delete'" do
        items = helper.keybindings_for_surface(:web)
                      .fetch("menus").fetch("channels").fetch("items")
        row = items.find { |i| i.fetch("key") == "-" }
        expect(row.fetch("label")).to eq("delete")
        expect(row.fetch("action")).to eq("type" => "bulk_delete")
      end

      it "renames channels bulk sync to plain 'sync'" do
        items = helper.keybindings_for_surface(:web)
                      .fetch("menus").fetch("channels").fetch("items")
        row = items.find { |i| i.fetch("key") == "y" }
        expect(row.fetch("label")).to eq("sync")
        expect(row.fetch("action")).to eq("type" => "bulk_sync")
      end

      it "renames videos bulk delete to plain 'delete'" do
        items = helper.keybindings_for_surface(:web)
                      .fetch("menus").fetch("videos").fetch("items")
        row = items.find { |i| i.fetch("key") == "-" }
        expect(row.fetch("label")).to eq("delete")
      end

      it "renames projects bulk delete to plain 'delete'" do
        items = helper.keybindings_for_surface(:web)
                      .fetch("menus").fetch("projects").fetch("items")
        row = items.find { |i| i.fetch("key") == "-" }
        expect(row.fetch("label")).to eq("delete")
      end

      it "renames games bulk delete + bulk resync to plain 'delete' / 'resync'" do
        items = helper.keybindings_for_surface(:web)
                      .fetch("menus").fetch("games").fetch("items")
        delete_row = items.find { |i| i.fetch("key") == "-" }
        resync_row = items.find { |i| i.fetch("key") == "r" }
        expect(delete_row.fetch("label")).to eq("delete")
        expect(resync_row.fetch("label")).to eq("resync")
      end

      it "renames bundles bulk resync to plain 'resync'" do
        items = helper.keybindings_for_surface(:web)
                      .fetch("menus").fetch("bundles").fetch("items")
        row = items.find { |i| i.fetch("key") == "r" }
        expect(row.fetch("label")).to eq("resync")
      end

      it "leaves no 'bulk …' or '(selection)' phrasing in any label" do
        menus = helper.keybindings_for_surface(:web).fetch("menus")
        offenders = menus.flat_map do |name, menu|
          menu.fetch("items").select do |i|
            label = i.fetch("label", "")
            label.start_with?("bulk ") || label.include?("(selection)")
          end.map { |i| [ name, i.fetch("key"), i.fetch("label") ] }
        end
        expect(offenders).to be_empty,
          "expected no 'bulk …' / '(selection)' labels, found #{offenders.inspect}"
      end
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
