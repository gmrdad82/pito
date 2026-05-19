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
# 2026-05-18 (revision 2) — the root menu was trimmed to the
# in-scope beta-3 areas only (/games + /settings + logout). The
# earlier flat 2-key bindings for calendar / channels / videos /
# projects / notifications / `G+` games-new and the `h` home direct
# entry were dropped. `G+` (renamed "add game") moved to
# `page_actions.games_index` because it is page-local to /games;
# `Gb add bundle` is the new 2-key sibling there too.
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

    describe "root menu — trimmed to /games + /settings + logout" do
      let(:items) do
        helper.keybindings_for_surface(:web)
              .fetch("menus").fetch("root").fetch("items")
      end

      it "exposes [Gl] games with a direct navigate action" do
        row = items.find { |i| i["key"] == "Gl" }
        expect(row).not_to be_nil
        expect(row.fetch("label")).to eq("games")
        expect(row.fetch("action")).to eq("type" => "navigate", "path" => "/games")
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

      # 2026-05-18 — the following keys were intentionally dropped
      # from the root menu in this revision. Each lock asserts the
      # absence so a regression that resurrects them fails fast.
      dropped_keys = %w[
        h
        cs cm ct c+
        Cl C+ C- Cy
        Vl V+ V-
        Pl P+ P-
        Nl Nu Nm
        G+
      ].freeze

      dropped_keys.each do |key|
        it "no longer ships the [#{key}] root binding (2026-05-18 trim)" do
          row = items.find { |i| i["key"] == key }
          expect(row).to be_nil,
            "expected the [#{key}] binding to be removed from the root menu"
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

    describe "page_actions.games_index — `G+` and `Gb` create-row bindings" do
      let(:rows) { helper.keybindings_for_surface(:web).fetch("page_actions").fetch("games_index") }

      it "exposes [G+] add game wired to open_modal_by_id → omnisearch-modal-games-index" do
        row = rows.find { |r| r.is_a?(Hash) && r["key"] == "G+" }
        expect(row).not_to be_nil, "expected a `G+` binding in games_index"
        expect(row.fetch("label")).to eq("add game")
        expect(row.fetch("action")).to eq(
          "type" => "open_modal_by_id",
          "target" => "omnisearch-modal-games-index"
        )
      end

      it "exposes [Gb] add bundle wired to the page_add_bundle action" do
        row = rows.find { |r| r.is_a?(Hash) && r["key"] == "Gb" }
        expect(row).not_to be_nil, "expected a `Gb` binding in games_index"
        expect(row.fetch("label")).to eq("add bundle")
        expect(row.fetch("action")).to eq("type" => "page_add_bundle")
      end

      it "ships [l] dark mode toggle at the top of the list" do
        row = rows.find { |r| r.is_a?(Hash) && r["key"] == "l" }
        expect(row).not_to be_nil
        expect(row.fetch("label")).to eq("dark mode toggle")
      end

      it "ships divider entries carrying `layout: grid_2col` to open the grid blocks" do
        grid_dividers = rows.select do |r|
          r.is_a?(Hash) && r["divider"] == true && r["layout"] == "grid_2col"
        end
        expect(grid_dividers.size).to eq(2),
          "expected 2 grid_2col dividers (one before the filter chips, one before G+/Gb)"
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
