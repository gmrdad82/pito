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

    it "renders the popup target dialog as a closed placeholder" do
      # 2026-05-17 — the popup migrated from `<div hidden>` to a native
      # `<dialog>` opened via `.showModal()` so the browser places it in
      # the top layer above other dialogs. Closed-state contract: the
      # `<dialog>` element renders without the `open` attribute.
      visit "/"
      expect(page).to have_css("dialog#leader-menu-popup:not([open])", visible: :all)
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

    it "places the [_] affordance inside the navbar, not the footer" do
      # 2026-05-18 — the `[_]` link was relocated from the footer into
      # the header navbar (immediately after `[settings]`). Lock the
      # location at the chrome level so a future regression — moving
      # the link back, or duplicating it across both regions — is
      # caught by this spec rather than only by visual review.
      visit "/"
      expect(page).to have_css("header a[data-action*='leader-menu#openRoot']", visible: :all)
      expect(page).not_to have_css("footer a[data-action*='leader-menu#openRoot']", visible: :all)
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
    # Phase 32 follow-up (2026-05-16). `/settings/tokens` and
    # `/settings/oauth_applications` web management UIs were dropped
    # — both surfaces moved to operator-only rake tasks
    # (`bin/rails pito:tokens:*` / `bin/rails pito:oauth_apps:*`).
    # 2026-05-16 (sessions revamp v2). `/settings/sessions` standalone
    # page is gone — sessions render INLINE in the Security pane on
    # `/settings`. The `/settings` entry in this audit list already
    # covers the surrounding shell.
    # Phase F3 (Beta 4, 2026-05-20) — `/settings/user` removed from
    # the audit list. The standalone profile page was cut per ADR 0016
    # (username + password management moved to operator-only rake tasks).
    AUDITED_PATHS = [
      "/",
      "/dashboard",
      "/channels",
      "/videos",
      "/projects",
      "/games",
      "/notifications",
      "/saved_views",
      "/settings",
      "/settings/security",
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
          "dialog#leader-menu-popup[data-leader-menu-target='popup']",
          visible: :all
        ), "expected #{path} to render the leader-menu popup target dialog"
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

  describe "flat 2-key dispatch schema (2026-05-18 — submenus dropped)" do
    # The nested-submenu UX (Space → `g` opens submenu → `l`
    # resolves) was replaced by direct 2-key dispatch (`Gl` games
    # list, `Cy` channels sync, `cs` calendar schedule, …) resolved
    # through the prefix accumulator the same way `page_actions`
    # bindings work. The root menu is the entire navigation surface;
    # no submenu maps remain in the schema.
    def payload_for(path)
      visit path
      script_node = page.find("script#pito-keybindings", visible: :all)
      JSON.parse(script_node.text(:all))
    end

    it "menus block has only the `root` key (no calendar/channels/videos/projects/games/notifications submenus)" do
      menus = payload_for("/").fetch("menus")
      expect(menus.keys).to eq([ "root" ])
    end

    # 2026-05-18 (revision 2) — the root menu was trimmed to the
    # in-scope beta-3 surfaces only (/games + /settings + logout).
    # Locked flat-binding contract — the three surviving direct-key
    # entries + the one surviving 2-key binding (`Gl`).
    flat_bindings = {
      "Gl" => { label: "games",   action: { "type" => "navigate", "path" => "/games" } },
      "S"  => { label: "settings", action: { "type" => "navigate", "path" => "/settings" } },
      "Q"  => { label: "logout",   action: { "type" => "logout" } }
    }.freeze

    flat_bindings.each do |key, expected|
      it "exposes the [#{key}] #{expected[:label]} binding with the right action" do
        items = payload_for("/").fetch("menus").fetch("root").fetch("items")
        row = items.find { |i| i["key"] == key }
        expect(row).not_to be_nil, "expected a flat binding with key #{key.inspect}"
        expect(row.fetch("label")).to eq(expected[:label])
        expect(row.fetch("action")).to eq(expected[:action])
        # Submenus are gone — no row should carry a `submenu` field.
        expect(row).not_to have_key("submenu")
      end
    end

    # 2026-05-18 (revision 2) — explicit dropped-key locks. Each
    # binding below was intentionally removed from the root menu in
    # this revision. The single test fails fast if any of them gets
    # resurrected by a stray YAML edit.
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
      it "does NOT ship the [#{key}] root binding (dropped 2026-05-18)" do
        items = payload_for("/").fetch("menus").fetch("root").fetch("items")
        row = items.find { |i| i["key"] == key }
        expect(row).to be_nil,
          "expected the [#{key}] binding to be absent from the trimmed root menu"
      end
    end

    it "no root row carries a `submenu` field (submenu UX dropped)" do
      items = payload_for("/").fetch("menus").fetch("root").fetch("items")
      offenders = items.select { |i| i.is_a?(Hash) && i.key?("submenu") }
      expect(offenders).to be_empty,
        "expected no root rows with `submenu`, found #{offenders.inspect}"
    end

    it "TUI-only [q] quit row is filtered out of the :web payload" do
      items = payload_for("/").fetch("menus").fetch("root").fetch("items")
      keys = items.map { |i| i["key"] }
      expect(keys).not_to include("q")
    end

    it "ships at least one divider entry between the navigation group and the logout row" do
      items = payload_for("/").fetch("menus").fetch("root").fetch("items")
      divider_count = items.count { |i| i.is_a?(Hash) && i["divider"] }
      expect(divider_count).to be >= 1
    end
  end

  describe "leader-menu popup div is permanent across Turbo navigations" do
    # The popup div survives Turbo Drive body swaps via the
    # `data-turbo-permanent` attribute. With the 2026-05-18 flat
    # 2-key dispatch every root binding fires a Turbo.visit on the
    # FIRST character of a multi-char key only after the second key
    # arrives (e.g. `Cl` → /channels), so the popup may briefly span
    # the prefix-armed window before the second key resolves. Marking
    # the popup div `data-turbo-permanent` keeps the chrome (and the
    # rehydrate path) consistent across navigations.
    it "renders the popup dialog with data-turbo-permanent" do
      visit "/"
      expect(page).to have_css(
        "dialog#leader-menu-popup[data-turbo-permanent]",
        visible: :all
      )
    end
  end

  describe "flat 2-key activation logic (2026-05-18 — submenu UX dropped)" do
    # rack_test has no JS engine, so we can't simulate keypress
    # SPACE → C → l interactively. The contract we CAN lock is the
    # source text of the controller's `activate` method + header
    # comment: the defensive `hasSubmenu` branch is preserved (so a
    # future schema can opt back in), the combined "fire action AND
    # drill" branch is gone, and the dispatch path resolves multi-char
    # keys via the prefix accumulator the same way `page_actions`
    # does. Pair with the schema lock above (root rows ship flat
    # 2-key bindings, no `submenu` field anywhere) so a regression
    # that re-introduces nested-submenu rows fails fast on both ends.
    let(:controller_source) do
      File.read(Rails.root.join("app/javascript/controllers/leader_menu_controller.js"))
    end

    it "activate() retains the defensive submenu branch (opens the submenu, no action fired)" do
      # The submenu branch stays as a safety net even though the
      # shipped YAML carries no `submenu` rows. If a future edit
      # accidentally drops this branch, opting back into a submenu
      # via the YAML would silently no-op — lock the shape.
      expect(controller_source).to match(
        /if\s*\(hasSubmenu\)\s*\{\s*this\.openMenu\(item\.submenu\)\s*return\s*\}/m
      )
    end

    it "drops the combined action+submenu branch" do
      # The legacy branch was `if (hasAction && hasSubmenu) { ... }` —
      # it fired the action with `closePopup: false` then drilled. The
      # 2026-05-10 revert removed that block; the 2026-05-18 flat-
      # dispatch reorg leaves it gone. A stray `action` next to a
      # `submenu` is silently ignored by the defensive branch above.
      expect(controller_source).not_to match(/if\s*\(\s*hasAction\s*&&\s*hasSubmenu\s*\)/),
        "expected the combined action+submenu branch to be removed from activate()"
    end

    it "documents the 2026-05-18 flat 2-key dispatch in the controller header" do
      # Top-of-file comment is the contract Rust-side maintainers read
      # first when keeping the TUI overlay (`extras/cli/src/ui/
      # leader_menu.rs`) aligned. Lock the new description so the docs
      # and code don't drift.
      expect(controller_source).to include("2026-05-18 architectural change")
      expect(controller_source).to include("flat 2-key dispatch")
      expect(controller_source).to include("Submenus are gone schema-wide")
    end

    it "schema-shape comment block documents the flat 2-key shape" do
      # The `Schema shape (…)` block is the second contract Rust-side
      # maintainers walk through. Lock the updated wording so the YAML
      # contract and the code description stay in lockstep.
      expect(controller_source).to include("Schema shape (2026-05-18 flat 2-key dispatch)")
      expect(controller_source).to include("No `submenu` field appears on")
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
      #
      # 2026-05-17 — `close()` also wipes `this.inlineMenus = {}` between
      # those two calls, so the gap-matcher must allow `{` / `}` chars
      # (the legacy `[^}]*` pattern would otherwise fail on the empty
      # object literal). Anchor on `close(` to bound the search to the
      # method body and trust the `.persistStack()` callsite ordering.
      expect(controller_source).to match(
        /close\([^)]*\)\s*\{[\s\S]*?this\.menuStack\s*=\s*\[\][\s\S]*?this\.persistStack\(\)/m
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
        "dialog#leader-menu-popup[data-leader-menu-target='popup']", visible: :all
      )
    end
  end

  describe "controller wiring structural lock (static-source)" do
    # Static-source counterparts to the runtime invariants that rack_test
    # cannot exercise. Each assertion locks ONE structural contract the
    # controller depends on so a rename / drop / refactor surfaces fast.
    # The runtime assertions in the prior describe blocks already cover
    # ancillary behaviors (turbo:visit, dialog-close cascade, etc.); the
    # asserts below are the foundational `connect()` wiring.
    let(:controller_source) do
      File.read(Rails.root.join("app/javascript/controllers/leader_menu_controller.js"))
    end

    it "registers a document-level keydown listener inside connect()" do
      # The leader popup's entire dispatch pivots on this single
      # listener. Lock the addEventListener call shape so a refactor
      # that moves the binding (or drops it) fails fast.
      expect(controller_source).to match(
        /document\.addEventListener\(\s*"keydown"\s*,\s*this\.boundKeydown\s*\)/
      )
    end

    it "binds the keydown handler reference in connect() for symmetric teardown" do
      # Stimulus controllers can be connected/disconnected many times
      # during a session (Turbo body swaps). The bound reference must
      # be cached so `removeEventListener` in disconnect() finds the
      # same function identity.
      expect(controller_source).to match(
        /this\.boundKeydown\s*=\s*this\.onKeydown\.bind\(this\)/
      )
    end

    it "loads the keybindings schema from the `pito-keybindings` JSON script tag" do
      # The schema is embedded as `<script id="pito-keybindings" type="application/json">`
      # by the layout (the runtime-side mount audit above asserts the
      # presence of the tag on every page). The controller parses it
      # via `JSON.parse` of the script node's textContent in connect().
      expect(controller_source).to match(
        /document\.getElementById\(\s*"pito-keybindings"\s*\)/
      )
      expect(controller_source).to match(/JSON\.parse\(\s*node\.textContent/)
    end

    it "implements the SPACE-prefix accumulator pattern" do
      # 2-key sequence support (A1) lives in `pendingPrefix` +
      # `handlePrefixKey`. Lock the existence of the state variable
      # and the dispatch entry point so a refactor that drops 2-key
      # sequences catches.
      expect(controller_source).to match(/this\.pendingPrefix\s*=\s*""/)
      expect(controller_source).to match(/handlePrefixKey\s*\(\s*key\s*\)\s*\{/)
      expect(controller_source).to match(/this\.pendingPrefix\s*\+=\s*key/)
    end

    it "exposes candidatesForPrefix so the 2-key matcher routes through one helper" do
      # The matcher must read the active menu's items AND any
      # page-actions / inline submenu so a single source of truth feeds
      # the exact-match / longer-prefix branches.
      expect(controller_source).to match(/candidatesForPrefix\s*\(\s*prefix\s*\)\s*\{/)
    end

    it "treats Escape as an intentional fall-through (no preventDefault, no close)" do
      # A4 (2026-05-17): Esc must NOT be handled by the controller while
      # the popup is open — it falls through to the parent <dialog>'s
      # native Esc handler. The controller's keydown branch for Esc is
      # an explicit `return` with no `preventDefault` and no `close()`
      # in between. Lock the literal `return` so a future "ergonomics"
      # tweak that adds `this.close()` here regresses A4 immediately.
      expect(controller_source).to match(
        /if\s*\(\s*event\.key\s*===\s*"Escape"\s*\)\s*return/
      )
    end

    it "closes the popup when ANY other <dialog> on the page closes" do
      # A4 cascade: when a parent dialog (bundle modal / IGDB add-game /
      # confirm dialog) is dismissed, the leader popup tears down too
      # so it never orphan-renders above a dismissed parent. The `close`
      # event listener is installed in capture phase because `close`
      # does not bubble on `<dialog>`.
      expect(controller_source).to match(
        /document\.addEventListener\(\s*"close"\s*,\s*this\.boundDialogClose\s*,\s*true\s*\)/
      )
      expect(controller_source).to match(/onDialogClose\s*\(\s*event\s*\)\s*\{/)
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
