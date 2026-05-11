require "rails_helper"

# Leader-menu unified schema — system-level chrome contract.
#
# The Stimulus controller's interactive behavior (SPACE opens popup,
# `Esc` closes, `Backspace` pops up one level, per-key activation)
# can't be exercised under rack_test — there's no JS engine in the
# default Capybara driver. What we CAN lock here is the layout
# chrome that the controller depends on: the `<body>` mount, the
# popup target div, the embedded schema script, and the visible
# `[_]` affordance that triggers the controller via Stimulus
# `data-action`. The interactive behavior is covered by the
# `keybindings_helper_spec` + `leader_menu_layout_spec` pair and
# the in-flight Rust cargo tests (TUI side).
RSpec.describe "Leader menu chrome", type: :system do
  before { driven_by(:rack_test) }

  describe "on the dashboard" do
    it "mounts the leader-menu Stimulus controller on <body>" do
      visit "/"
      expect(page).to have_css("body[data-controller~='leader-menu']", visible: :all)
    end

    it "renders the popup target div as a hidden placeholder" do
      visit "/"
      expect(page).to have_css("div#leader-menu-popup[hidden]", visible: :all)
    end

    it "embeds the keybindings schema as a JSON script tag" do
      visit "/"
      expect(page).to have_css(
        "script#pito-keybindings[type='application/json']",
        visible: :all
      )
    end

    it "renders the visible [_] affordance wired to leader-menu#openRoot" do
      visit "/"
      # The bracketed link wraps the `_` glyph in a `<span class="bl">`;
      # we resolve the anchor by `data-action` attribute and assert
      # both the action wiring AND the visible glyph survive.
      anchor = find("a[data-action*='leader-menu#openRoot']")
      expect(anchor["data-action"]).to include("click->leader-menu#openRoot")
      expect(anchor[:href]).to eq("#")
      expect(anchor).to have_css("span.bl", text: "_")
    end
  end

  describe "on the channels index" do
    it "mounts the leader-menu controller on every page that renders the chrome" do
      visit "/channels"
      expect(page).to have_css("body[data-controller~='leader-menu']", visible: :all)
      expect(page).to have_css("script#pito-keybindings", visible: :all)
    end
  end

  describe "schema-driven menu shape (lock the contract the JS will consume)" do
    def payload_for(path)
      visit path
      script_node = page.find("script#pito-keybindings", visible: :all)
      JSON.parse(script_node.text(:all))
    end

    it "exposes the calendar submenu via the JSON payload" do
      calendar = payload_for("/").fetch("menus").fetch("calendar").fetch("items")
      keys = calendar.map { |i| i.fetch("key") }
      expect(keys).to match_array(%w[s m t +])
    end

    it "exposes the channels submenu including the delete + sync keys" do
      channels = payload_for("/").fetch("menus").fetch("channels").fetch("items")
      keys = channels.map { |i| i.fetch("key") }
      expect(keys).to include("l", "+", "-", "y")
    end

    it "channels submenu uses the cleaned-up labels (delete / sync, no 'bulk')" do
      channels = payload_for("/").fetch("menus").fetch("channels").fetch("items")
      labels = channels.map { |i| i.fetch("label") }
      expect(labels).to include("delete", "sync")
      expect(labels).not_to include("bulk delete (selection)", "bulk sync (selection)")
    end

    it "channels submenu does NOT include the [b] bulk toggle (legacy) entry" do
      channels = payload_for("/").fetch("menus").fetch("channels").fetch("items")
      keys = channels.map { |i| i.fetch("key") }
      expect(keys).not_to include("b")
    end

    it "root [C] channels row carries BOTH navigate + submenu" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "C" }
      expect(row.fetch("action")).to eq("type" => "navigate", "path" => "/channels")
      expect(row.fetch("submenu")).to eq("channels")
    end

    it "root [V] videos row carries BOTH navigate + submenu" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "V" }
      expect(row.fetch("action")).to eq("type" => "navigate", "path" => "/videos")
      expect(row.fetch("submenu")).to eq("videos")
    end

    it "root [P] projects row carries BOTH navigate + submenu" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "P" }
      expect(row.fetch("action")).to eq("type" => "navigate", "path" => "/projects")
      expect(row.fetch("submenu")).to eq("projects")
    end

    it "root [G] games row carries BOTH navigate + submenu" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "G" }
      expect(row.fetch("action")).to eq("type" => "navigate", "path" => "/games")
      expect(row.fetch("submenu")).to eq("games")
    end

    it "root [c] calendar row carries BOTH navigate + submenu" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "c" }
      expect(row.fetch("action")).to eq("type" => "navigate", "path" => "/calendar")
      expect(row.fetch("submenu")).to eq("calendar")
    end

    it "root [N] notifications row carries BOTH open-modal action + submenu" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "N" }
      expect(row.fetch("action")).to eq("type" => "open", "target" => "notifications_modal")
      expect(row.fetch("submenu")).to eq("notifications")
    end

    it "channels submenu [l] list still navigates to /channels (muscle memory)" do
      channels = payload_for("/").fetch("menus").fetch("channels").fetch("items")
      list_row = channels.find { |i| i.fetch("key") == "l" }
      expect(list_row.fetch("action")).to eq("type" => "navigate", "path" => "/channels")
    end

    it "channels submenu [+] add navigates to /channels (Phase 24 — banner-based add)" do
      channels = payload_for("/").fetch("menus").fetch("channels").fetch("items")
      add_row = channels.find { |i| i.fetch("key") == "+" }
      expect(add_row.fetch("action")).to eq(
        "type" => "navigate", "path" => "/channels"
      )
    end
  end

  describe "leader-menu popup div is permanent across Turbo navigations" do
    # The Stimulus controller relies on the popup div surviving a
    # Turbo Drive body swap when a root-menu item carries BOTH a
    # navigate action AND a submenu (e.g. pressing [C] navigates to
    # /channels AND drills into the channels submenu so the user sees
    # the next-level options). The cross-swap survival is gated by
    # the `data-turbo-permanent` attribute on the popup div; lock
    # that attribute here so it cannot regress quietly.
    it "renders the popup div with data-turbo-permanent" do
      visit "/"
      expect(page).to have_css(
        "div#leader-menu-popup[data-turbo-permanent]",
        visible: :all
      )
    end
  end
end
