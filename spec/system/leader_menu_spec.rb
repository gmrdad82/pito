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

  # Cross-page audit (2026-05-10). Every web page that renders the
  # application layout chrome MUST mount the `leader-menu` Stimulus
  # controller AND embed the `<script id="pito-keybindings">` JSON
  # payload AND render the `#leader-menu-popup` target div. Pages
  # that strip the chrome (`content_for(:hide_chrome, true)` —
  # sessions/new, doorkeeper authorizations, login challenges) STILL
  # mount the controller and the schema because the body-level mount
  # is intentionally outside the `hide_chrome` block. The only page
  # in the app that legitimately bypasses the layout is the
  # `/calendar` thin router shell (`render layout: false`) — it's a
  # ~1s redirect, not a user destination, so the leader popup has
  # no use there.
  describe "leader-menu mount audit across top-level pages" do
    AUDITED_PATHS = [
      "/",
      "/dashboard",
      "/channels",
      "/videos",
      "/projects",
      "/games",
      "/bundles",
      "/notifications",
      "/saved_views",
      "/settings",
      "/settings/user",
      "/settings/security",
      "/settings/tokens",
      "/settings/sessions",
      "/settings/oauth_applications",
      "/calendar/schedule",
      "/notes"
    ].freeze

    AUDITED_PATHS.each do |path|
      it "mounts the leader-menu controller + schema + popup target on #{path}" do
        visit path
        expect(page).to have_css(
          "body[data-controller~='leader-menu']", visible: :all
        ), "expected #{path} to mount the leader-menu Stimulus controller"
        expect(page).to have_css(
          "script#pito-keybindings[type='application/json']", visible: :all
        ), "expected #{path} to embed the keybindings schema"
        expect(page).to have_css(
          "div#leader-menu-popup[data-leader-menu-target='popup']",
          visible: :all
        ), "expected #{path} to render the leader-menu popup target div"
      end
    end

    # Chrome-suppressed pages (sessions/new, doorkeeper authorizations,
    # login challenges) hide the nav/footer but STILL mount the
    # leader-menu controller + schema at the body level. Pressing SPACE
    # on the login page opens the popup so power users can press
    # `h` (home) or `S` (settings) once authenticated; the popup itself
    # paints without depending on the suppressed nav.
    UNAUTHENTICATED_PATHS = [ "/login" ].freeze

    UNAUTHENTICATED_PATHS.each do |path|
      it "still mounts the leader-menu controller on #{path} (chrome-suppressed)", :unauthenticated do
        visit path
        expect(page).to have_css(
          "body[data-controller~='leader-menu']", visible: :all
        ), "expected #{path} to mount the leader-menu Stimulus controller even with chrome suppressed"
        expect(page).to have_css(
          "script#pito-keybindings", visible: :all
        ), "expected #{path} to embed the keybindings schema even with chrome suppressed"
      end
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

    # 2026-05-10 revert: root-menu rows that point to a submenu DROP
    # the `action` field. Pressing C/V/P/G/c/N at the root drills into
    # the named submenu ONLY; the user must press `l` (list) inside
    # the submenu to actually navigate.
    it "root [C] channels row is submenu-only (no action)" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "C" }
      expect(row.fetch("submenu")).to eq("channels")
      expect(row).not_to have_key("action")
    end

    it "root [V] videos row is submenu-only (no action)" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "V" }
      expect(row.fetch("submenu")).to eq("videos")
      expect(row).not_to have_key("action")
    end

    it "root [P] projects row is submenu-only (no action)" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "P" }
      expect(row.fetch("submenu")).to eq("projects")
      expect(row).not_to have_key("action")
    end

    it "root [G] games row is submenu-only (no action)" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "G" }
      expect(row.fetch("submenu")).to eq("games")
      expect(row).not_to have_key("action")
    end

    it "root [c] calendar row is submenu-only (no action)" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "c" }
      expect(row.fetch("submenu")).to eq("calendar")
      expect(row).not_to have_key("action")
    end

    it "root [N] notifications row is submenu-only (no action)" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "N" }
      expect(row.fetch("submenu")).to eq("notifications")
      expect(row).not_to have_key("action")
    end

    it "root [S] settings row keeps direct navigation (no submenu)" do
      # S is the only capital-letter root row that retains a direct
      # `action: navigate` — it has no submenu, so pressing S at the
      # root jumps straight to /settings.
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "S" }
      expect(row.fetch("action")).to eq("type" => "navigate", "path" => "/settings")
      expect(row).not_to have_key("submenu")
    end

    it "root [h] home row keeps direct navigation (no submenu)" do
      root = payload_for("/").fetch("menus").fetch("root").fetch("items")
      row = root.find { |i| i.fetch("key") == "h" }
      expect(row.fetch("action")).to eq("type" => "navigate", "path" => "/")
      expect(row).not_to have_key("submenu")
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
    # The popup div survives Turbo Drive body swaps via the
    # `data-turbo-permanent` attribute. After the 2026-05-10 revert
    # root-menu rows with a submenu drop the navigate action — pressing
    # `C` at the root only drills into the channels submenu (no
    # background navigation). The popup is still marked permanent so a
    # future entry that DOES navigate (e.g. submenu `l list`) can
    # preserve the popup across the page swap if needed.
    it "renders the popup div with data-turbo-permanent" do
      visit "/"
      expect(page).to have_css(
        "div#leader-menu-popup[data-turbo-permanent]",
        visible: :all
      )
    end
  end

  describe "submenu-only activation logic (2026-05-10 revert source lock)" do
    # rack_test has no JS engine, so we can't simulate keypress
    # SPACE → C → l interactively. The contract we CAN lock is the
    # source text of the controller's `activate` method: submenu takes
    # precedence, the combined "fire action AND drill" branch is gone,
    # and submenu-only rows do NOT navigate as a side effect. Pair
    # with the schema lock above (root C/V/P/G/c/N rows are
    # submenu-only) so a regression that re-introduces dual-action
    # rows OR resurrects the combined branch fails fast.
    let(:controller_source) do
      File.read(Rails.root.join("app/javascript/controllers/leader_menu_controller.js"))
    end

    it "activate() drills into the submenu without firing the action" do
      # The submenu branch returns immediately after `openMenu`. If a
      # future edit re-introduces a `fireAction` call inside the
      # submenu branch, the order of these two lines (or the `return`)
      # breaks and this assertion catches it.
      expect(controller_source).to match(
        /if\s*\(hasSubmenu\)\s*\{\s*this\.openMenu\(item\.submenu\)\s*return\s*\}/m
      )
    end

    it "drops the combined action+submenu branch" do
      # The legacy branch was `if (hasAction && hasSubmenu) { ... }` —
      # it fired the action with `closePopup: false` then drilled. The
      # revert removes that block entirely so a stray `action` next to
      # a `submenu` is silently ignored.
      expect(controller_source).not_to match(/if\s*\(\s*hasAction\s*&&\s*hasSubmenu\s*\)/),
        "expected the combined action+submenu branch to be removed from activate()"
    end

    it "documents the 2026-05-10 revert in the controller header" do
      # Top-of-file comment is the contract Rust-side maintainers read
      # first when keeping the TUI overlay (`extras/cli/src/ui/
      # leader_menu.rs`) aligned. Lock the new description so the docs
      # and code don't drift.
      expect(controller_source).to include("2026-05-10 revert")
      expect(controller_source).to include("submenu ONLY")
    end
  end

  describe "dismiss-on-navigate (2026-05-10): popup closes on every Turbo navigation" do
    # rack_test has no JS engine, so we can't synthesize a `turbo:visit`
    # event and watch the popup state flip. The contract we CAN lock is
    # the source text of the Stimulus controller: the `connect` method
    # MUST register a `turbo:visit` listener, the `disconnect` method
    # MUST tear it down, and the handler MUST call `close()` so the
    # popup vanishes the moment any navigation begins (whether the
    # leader-menu fired it, the user clicked a link outside, or a form
    # submitted). The TUI side already closes on every resolved
    # keybinding action via the `Resolved` enum; this lock keeps the
    # web side aligned.
    let(:controller_source) do
      File.read(Rails.root.join("app/javascript/controllers/leader_menu_controller.js"))
    end

    it "registers a turbo:visit listener inside connect()" do
      # The listener uses the bound handler reference so disconnect()
      # can pair the removal with the same function identity. Locking
      # the addEventListener call shape catches a regression that
      # forgets to wire the dismiss-on-navigate path.
      expect(controller_source).to match(
        /document\.addEventListener\(\s*"turbo:visit"\s*,\s*this\.boundTurboVisit\s*\)/
      )
    end

    it "binds the turbo:visit handler reference in connect() for symmetric teardown" do
      # Stimulus controllers can be connected/disconnected many times
      # during a session (Turbo body swaps, modal frame loads). The
      # bound reference MUST be cached on the instance so
      # `removeEventListener` in disconnect() finds the same function
      # identity it registered.
      expect(controller_source).to match(
        /this\.boundTurboVisit\s*=\s*this\.onTurboVisit\.bind\(this\)/
      )
    end

    it "removes the turbo:visit listener inside disconnect()" do
      # Without teardown a body swap that recreates the controller would
      # leak listeners — each prior instance would still call close()
      # on every nav. Lock the symmetric removal.
      expect(controller_source).to match(
        /removeEventListener\(\s*"turbo:visit"\s*,\s*this\.boundTurboVisit\s*\)/
      )
    end

    it "defines an onTurboVisit handler that closes the popup" do
      # The handler is intentionally trivial: close(). It must not
      # guard on isOpen() because close() is idempotent AND it also
      # clears the persisted menu stack from sessionStorage so the
      # destination page boots without rehydrating the popup.
      expect(controller_source).to match(
        /onTurboVisit\([^)]*\)\s*\{[^}]*this\.close\(\)[^}]*\}/m
      )
    end

    it "documents the dismiss-on-navigate behavior in the controller header" do
      # The top-of-file comment is the contract Rust-side maintainers
      # read first when keeping the TUI overlay aligned with the web
      # popup. Lock the new description so docs and code don't drift.
      expect(controller_source).to include("Dismiss-on-navigate")
      expect(controller_source).to include("turbo:visit")
    end

    it "keeps the outside-click handler intact (clicks on links outside still dismiss)" do
      # Belt-and-braces: even on surfaces where Turbo is unavailable
      # (auth pages with chrome hidden) OR where a click triggers a
      # non-Turbo navigation, the outside-click listener still closes
      # the popup. Lock both code paths so a future refactor that
      # consolidates listeners doesn't accidentally drop one.
      expect(controller_source).to match(/onOutsideClick\([^)]*\)/)
      expect(controller_source).to include("document.addEventListener(\"click\", this.boundOutside, true)")
    end

    it "close() empties the menu stack and clears the persisted sessionStorage entry" do
      # The popup must not rehydrate on the destination page. close()
      # already empties this.menuStack and calls persistStack(), which
      # removes the storage key when the stack is empty. Lock the
      # ordering so a refactor that splits close() doesn't break the
      # rehydrate-suppression path.
      expect(controller_source).to match(
        /close\([^)]*\)\s*\{[^}]*this\.menuStack\s*=\s*\[\][^}]*this\.persistStack\(\)/m
      )
    end
  end

  describe "form-control pass-through (2026-05-11): SPACE on a focused input / button defers" do
    # rack_test has no JS engine, so the runtime focus state can't be
    # exercised directly. The contract we CAN lock is the source text
    # of the Stimulus controller's `isEditableTarget` selector — every
    # form-entry surface listed in the user direction must appear so
    # SPACE on a focused control passes through to native browser
    # behaviour instead of opening the popup.
    #
    # User direction (2026-05-11): "if focus is on an input field or
    # textarea or button, or checkbox, it should not trigger as that's
    # form functionality."
    #
    # Concrete consequences locked here:
    #   * <input> covers checkbox + radio + every text-style type,
    #     so the selector entry `input` is enough (no separate
    #     `input[type=checkbox]` entry needed).
    #   * <button> joins the skip set so Tab-then-SPACE on the
    #     [update] button in /settings submits the form rather than
    #     opening the popup.
    #   * <textarea>, <select>, [contenteditable] stay in the set
    #     so the previous behaviour for text entry surfaces does
    #     not regress.
    let(:controller_source) do
      File.read(Rails.root.join("app/javascript/controllers/leader_menu_controller.js"))
    end

    it "isEditableTarget skips <input>" do
      expect(controller_source).to match(/isEditableTarget\([^}]*matches\([^)]*\binput\b/m)
    end

    it "isEditableTarget skips <textarea>" do
      expect(controller_source).to match(/isEditableTarget\([^}]*matches\([^)]*\btextarea\b/m)
    end

    it "isEditableTarget skips <select>" do
      expect(controller_source).to match(/isEditableTarget\([^}]*matches\([^)]*\bselect\b/m)
    end

    it "isEditableTarget skips <button>" do
      # The whole reason for the 2026-05-11 fix. A focused [update]
      # button on /settings must activate on SPACE (browser default),
      # NOT open the leader popup.
      expect(controller_source).to match(/isEditableTarget\([^}]*matches\([^)]*\bbutton\b/m)
    end

    it "isEditableTarget skips [contenteditable]" do
      expect(controller_source).to match(/isEditableTarget\([^}]*matches\([^)]*contenteditable/m)
    end

    it "documents the form-control pass-through in the controller header" do
      # The top-of-file comment is the contract Rust-side maintainers
      # read first when keeping the TUI overlay aligned with the web
      # popup. Lock the new description so docs and code don't drift.
      expect(controller_source).to include("Form-control pass-through")
      expect(controller_source).to include("2026-05-11")
    end

    it "/settings still mounts the leader-menu controller (regression for Fix 1)" do
      # The original bug report ("keyboard navigation is not available
      # at /settings") was traced to focus landing on a form control
      # rather than missing chrome. We keep this lock here alongside
      # the AUDITED_PATHS sweep above so any future regression of the
      # /settings chrome mount fails fast inside this describe block.
      visit "/settings"
      expect(page).to have_css(
        "body[data-controller~='leader-menu']", visible: :all
      )
      expect(page).to have_css(
        "script#pito-keybindings[type='application/json']", visible: :all
      )
      expect(page).to have_css(
        "div#leader-menu-popup[data-leader-menu-target='popup']", visible: :all
      )
    end
  end

  describe "popup row rendering — keys are rendered without surrounding brackets" do
    # rack_test has no JS engine, so the popup card is never built at
    # runtime in this suite; the contract we CAN lock is the source
    # text the Stimulus controller emits for each row. The previous
    # rendering wrapped the key glyph in `[…]` (so rows read
    # `[l] list`, `[+] add`, `[Q] quit + logout`); the new rendering
    # drops the brackets and relies on `.leader-menu-key { min-width:
    # 28px }` for monospace alignment so rows read `l  list`, `+  add`,
    # `Q  quit + logout`. Locking the absence of the bracket template
    # here catches a regression that re-introduces inline brackets.
    let(:controller_source) do
      File.read(Rails.root.join("app/javascript/controllers/leader_menu_controller.js"))
    end

    it "does not wrap the key glyph in a bracket template literal" do
      # The legacy template was `[${this.displayKey(item.key)}]`. Any
      # variant that surrounds the displayKey expression with literal
      # `[` and `]` characters fails this guard.
      expect(controller_source).not_to match(/`\[\$\{[^`]*displayKey[^`]*\}\]`/),
        "expected the row-render to drop the [..] brackets around the key glyph"
    end

    it "assigns the displayKey expression directly to keySpan.textContent" do
      # Positive lock: the row-render keeps the displayKey call but
      # writes it straight to textContent (no surrounding string
      # interpolation). If a future refactor moves to a builder
      # function, replace this guard with one that asserts the same
      # post-condition on the new surface.
      expect(controller_source).to match(/keySpan\.textContent\s*=\s*this\.displayKey\(item\.key\)/)
    end

    it "documents the bracket-less rendering in the header comment" do
      # The top-of-file comment is the contract Rust-side maintainers
      # read first when keeping the TUI overlay (`extras/cli/src/ui/
      # leader_menu.rs`) aligned with the web popup. Lock the new
      # description so docs and code don't drift.
      expect(controller_source).to include("`key  label` rows")
    end
  end
end
