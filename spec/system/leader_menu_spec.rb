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
    it "exposes the calendar submenu via the JSON payload" do
      visit "/"
      script_node = page.find("script#pito-keybindings", visible: :all)
      payload = JSON.parse(script_node.text(:all))
      calendar = payload.fetch("menus").fetch("calendar").fetch("items")
      keys = calendar.map { |i| i.fetch("key") }
      expect(keys).to match_array(%w[s m t +])
    end

    it "exposes the channels submenu including the bulk delete + bulk sync keys" do
      visit "/"
      script_node = page.find("script#pito-keybindings", visible: :all)
      payload = JSON.parse(script_node.text(:all))
      channels = payload.fetch("menus").fetch("channels").fetch("items")
      keys = channels.map { |i| i.fetch("key") }
      expect(keys).to include("l", "+", "-", "y")
    end
  end
end
