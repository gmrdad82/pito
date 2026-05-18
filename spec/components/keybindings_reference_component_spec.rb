require "rails_helper"

# 2026-05-18 — KeybindingsReferenceComponent renders the navigation
# map as a flat 2-key dispatch list. The earlier nested-submenu UX
# (root row → opens sub-menu → second key resolves the action) was
# dropped in favour of direct 2-key resolution (`Cl` channels list,
# `Gl` games list, `cs` calendar schedule, …) resolved through the
# same prefix accumulator that powers `page_actions` 2-key bindings.
#
# The component exposes:
#   * `page_actions`   — per-page action rows (filter chips on /games,
#                        sr/vr/da/dd/sa/sd on /settings, etc.). Empty
#                        when the page is deny-listed or the YAML has
#                        no entry AND no `default:` fallback.
#   * `navigation_items` — the flat list of root-menu items. Each row
#                        is either a binding (`key`, `label`, `action`)
#                        or a divider (`{ "divider" => true }`).
#
# This spec exercises both accessors against the real
# `config/keybindings.yml` so the wiring between YAML / loader /
# component stays load-bearing.
RSpec.describe KeybindingsReferenceComponent, type: :component do
  describe "#navigation_items (flat 2-key list)" do
    let(:items) { described_class.new.navigation_items }

    it "returns an Array of row hashes" do
      expect(items).to be_an(Array)
      expect(items).to all(be_a(Hash))
    end

    it "exposes the [h] home direct binding" do
      home = items.find { |i| i["key"] == "h" }
      expect(home).not_to be_nil
      expect(home["label"]).to eq("home")
      expect(home["action"]).to eq("type" => "navigate", "path" => "/")
    end

    it "exposes the [S] settings direct binding" do
      settings = items.find { |i| i["key"] == "S" }
      expect(settings).not_to be_nil
      expect(settings["label"]).to eq("settings")
      expect(settings["action"]).to eq("type" => "navigate", "path" => "/settings")
    end

    it "exposes the [Q] logout direct binding" do
      logout = items.find { |i| i["key"] == "Q" }
      expect(logout).not_to be_nil
      expect(logout["label"]).to eq("logout")
      expect(logout["action"]).to eq("type" => "logout")
    end

    # Calendar prefix (`c`) — four bindings under the lowercase letter.
    %w[cs cm ct c+].each do |key|
      it "exposes the [#{key}] calendar binding (2-key, lowercase prefix)" do
        row = items.find { |i| i["key"] == key }
        expect(row).not_to be_nil, "expected a flat binding for #{key.inspect}"
        expect(row["label"]).to start_with("calendar ")
      end
    end

    # Channels prefix (`C`) — four bindings under the capital letter.
    %w[Cl C+ C- Cy].each do |key|
      it "exposes the [#{key}] channels binding (2-key, capital prefix)" do
        row = items.find { |i| i["key"] == key }
        expect(row).not_to be_nil, "expected a flat binding for #{key.inspect}"
        expect(row["label"]).to start_with("channels ")
      end
    end

    # Videos, projects, games, notifications follow the same shape.
    %w[Vl V+ V- Pl P+ P- Gl G+ Nl Nu Nm].each do |key|
      it "exposes the [#{key}] flat binding with the matching prefix label" do
        row = items.find { |i| i["key"] == key }
        expect(row).not_to be_nil, "expected a flat binding for #{key.inspect}"
        expect(row["label"]).to match(/\A(videos|projects|games|notifications) /)
      end
    end

    it "ships no row carrying a `submenu` field (submenu UX dropped 2026-05-18)" do
      offenders = items.select { |i| i.key?("submenu") }
      expect(offenders).to be_empty,
        "expected no rows with `submenu`, found #{offenders.inspect}"
    end

    it "no two binding rows share the same key (collision guard)" do
      keys = items.reject { |i| i["divider"] }.map { |i| i["key"] }
      expect(keys.uniq.length).to eq(keys.length),
        "expected every binding key to be unique, got duplicates in #{keys.inspect}"
    end

    it "includes divider entries between logical groups" do
      dividers = items.select { |i| i["divider"] == true }
      expect(dividers.length).to be >= 8
    end
  end

  describe "render" do
    it "paints a flat row per binding (key + label, no submenu arrow)" do
      render_inline(described_class.new)
      # Spot-check a few rows — the full table is locked by the
      # `#navigation_items` describe block above.
      expect(page).to have_css(".keybindings-navigation kbd", text: "h")
      expect(page).to have_css(".keybindings-navigation kbd", text: "Cl")
      expect(page).to have_css(".keybindings-navigation kbd", text: "Gl")
      expect(page).to have_css(".keybindings-navigation kbd", text: "cs")
      expect(page).to have_css(".keybindings-navigation span", text: "channels list")
      expect(page).to have_css(".keybindings-navigation span", text: "games list")
      expect(page).to have_css(".keybindings-navigation span", text: "calendar schedule")
    end

    it "paints divider entries as hairlines (non-interactive)" do
      render_inline(described_class.new)
      expect(page).to have_css(".keybindings-navigation hr.keybindings-divider")
    end

    it "does NOT render a submenu arrow on any row (no `→ <submenu>` text)" do
      render_inline(described_class.new)
      # The legacy template wrote `&rarr; <submenu>` on rows carrying
      # a `submenu` field. With the field removed schema-wide, no row
      # should render the arrow glyph.
      navigation = page.find(".keybindings-navigation")
      expect(navigation.text).not_to include("→")
    end

    it "does NOT render legacy menu-section labels (channels / videos / ...) as section headings" do
      # The earlier template iterated `navigation_menus.each` and
      # rendered the menu_key as a sub-heading. The flat list has no
      # such sub-headings — only the single `navigation` h3 and the
      # row content. Lock the absence of stale sub-heading divs.
      render_inline(described_class.new)
      expect(page).not_to have_css(".keybindings-menu-label", text: "channels")
      expect(page).not_to have_css(".keybindings-menu-label", text: "games")
      expect(page).not_to have_css(".keybindings-menu-label", text: "calendar")
    end
  end

  describe "page_actions accessor (regression — unchanged surface)" do
    it "returns [] when initialized with no page_key" do
      expect(described_class.new.page_actions).to eq([])
    end

    it "returns [] for a deny-listed page key" do
      expect(described_class.new(page_key: "admin").page_actions).to eq([])
    end

    it "resolves the games_index page_actions when given that key" do
      rows = described_class.new(page_key: "games_index").page_actions
      keys = rows.reject { |r| r["divider"] }.map { |r| r["key"] }
      expect(keys).to include("l", "/", "fr", "fo", "fP")
    end
  end
end
