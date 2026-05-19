require "rails_helper"

# 2026-05-18 (Wave F consolidation) — static-source structural lock for
# the `leader-menu` Stimulus controller
# (`app/javascript/controllers/leader_menu_controller.js`).
#
# Chrome — popup-open / popup-close / 2-key dispatch in a real browser —
# is covered by `spec/system/leader_menu_spec.rb`. This file pins the
# handler-level surface: target declarations, the Space/Esc/Backspace
# branches, the named action handlers wired through the YAML dispatch
# table, the BackSpace prefix accumulator, and the inactivity-timer
# exact-match grace path.
#
# Architecture references the spec is locking:
#   - 2026-05-18 architectural change — flat 2-key dispatch (no nested
#     root submenus; defensive `if (hasSubmenu)` branch stays).
#   - A1 (prefix accumulator), A3 (Space toggles), A4 (Esc falls
#     through to parent <dialog>).
#   - Phase C inactivity-timer exact-match grace (`d` dark mode vs
#     `da` / `dd` on /settings).
#   - Mandatory-2FA enrollment gate (`<meta name="pito-enroll-totp-gate">`).
#   - The named action handlers (pageSync, pageDelete, pageAddBundle,
#     openModalById, …) inlined onto this controller so dispatch is a
#     direct method call. The legacy `theme_toggle` / `themeToggle()`
#     action was removed alongside the single-theme cleanup
#     (2026-05-19); see the comment above `fireAction`.
RSpec.describe "leader_menu_controller.js" do
  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/leader_menu_controller.js")
    )
  end

  describe "controller declaration" do
    it "exports a default Stimulus Controller subclass" do
      expect(controller_source).to match(
        /export\s+default\s+class\s+extends\s+Controller/
      )
    end

    it "declares `popup` as a Stimulus target" do
      expect(controller_source).to match(
        /static\s+targets\s*=\s*\[\s*"popup"\s*\]/
      )
    end
  end

  describe "lifecycle wiring" do
    it "defines connect() and disconnect()" do
      expect(controller_source).to match(/connect\s*\(\s*\)\s*\{/)
      expect(controller_source).to match(/disconnect\s*\(\s*\)\s*\{/)
    end

    it "registers a document keydown listener in connect()" do
      connect_body = controller_source[/connect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(connect_body).to match(
        /document\.addEventListener\(\s*"keydown"\s*,\s*this\.boundKeydown\s*\)/
      )
    end

    it "registers a capture-phase document `close` listener for parent-dialog dismiss" do
      # When a parent <dialog> closes (Esc-pass-through), the leader
      # popup must close alongside via `onDialogClose`. `close` does
      # not bubble on <dialog>, so the listener uses capture=true.
      connect_body = controller_source[/connect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(connect_body).to match(
        /document\.addEventListener\(\s*"close"\s*,\s*this\.boundDialogClose\s*,\s*true\s*\)/
      )
    end

    it "registers a `turbo:visit` listener so the popup closes on every navigation" do
      connect_body = controller_source[/connect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(connect_body).to match(
        /document\.addEventListener\(\s*"turbo:visit"\s*,\s*this\.boundTurboVisit\s*\)/
      )
    end

    it "tears every listener down in disconnect()" do
      disconnect_body = controller_source[/disconnect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(disconnect_body).to include('removeEventListener("keydown"')
      expect(disconnect_body).to include('removeEventListener("click"')
      expect(disconnect_body).to include('removeEventListener("turbo:visit"')
      expect(disconnect_body).to include('removeEventListener("close"')
    end

    it "clears any pending prefix timer on disconnect" do
      disconnect_body = controller_source[/disconnect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(disconnect_body).to include("clearTimeout(this.prefixTimer)")
    end
  end

  describe "schema bootstrap from <script id=pito-keybindings>" do
    it "reads the embedded schema JSON via `pito-keybindings`" do
      expect(controller_source).to match(
        /document\.getElementById\(\s*"pito-keybindings"\s*\)/
      )
      expect(controller_source).to match(/JSON\.parse\(\s*node\.textContent/)
    end

    it "no-ops onKeydown when the schema is missing or malformed" do
      on_keydown_body = controller_source[/onKeydown\s*\(\s*event\s*\)\s*\{[\s\S]*?(?=^\s{2}handlePrefixKey)/m].to_s
      expect(on_keydown_body).to match(/if\s*\(\s*!this\.schema\s*\)\s*return/)
    end
  end

  describe "mandatory-2FA enrollment gate" do
    it "defines `enrollTotpGateActive` reading the head `<meta>` tag" do
      expect(controller_source).to match(
        /meta\[name="pito-enroll-totp-gate"\]/
      )
      expect(controller_source).to match(/content"?\s*\)\s*===\s*"yes"/)
    end

    it "short-circuits onKeydown when the enrollment gate is active" do
      on_keydown_body = controller_source[/onKeydown\s*\(\s*event\s*\)\s*\{[\s\S]*?(?=^\s{2}handlePrefixKey)/m].to_s
      expect(on_keydown_body).to match(/if\s*\(\s*enrollTotpGateActive\(\)\s*\)\s*return/)
    end
  end

  describe "onKeydown — Space / Esc / Backspace handling" do
    let(:on_keydown_body) do
      controller_source[/onKeydown\s*\(\s*event\s*\)\s*\{[\s\S]*?(?=^\s{2}handlePrefixKey)/m].to_s
    end

    it "skips when focus is on an editable target (input/textarea/select/button/contenteditable)" do
      # The form-control pass-through is what makes /settings (dense
      # with form controls) usable; SPACE on a focused [update] button
      # must submit the form, not open the popup.
      expect(on_keydown_body).to match(/if\s*\(\s*this\.isEditableTarget\(\s*event\.target\s*\)\s*\)\s*return/)
    end

    it "ignores Meta / Ctrl / Alt modified keystrokes" do
      expect(on_keydown_body).to match(
        /event\.metaKey\s*\|\|\s*event\.ctrlKey\s*\|\|\s*event\.altKey/
      )
    end

    it "A4: Esc passthrough — NOT handled while the popup is open" do
      # The leader popup never absorbs Esc. The parent <dialog>'s
      # native handler fires; the leader closes via the bubbling
      # `close` event handled by onDialogClose.
      expect(on_keydown_body).to match(
        /event\.key\s*===\s*"Escape"\s*\)\s*return/
      )
    end

    it "A1: Backspace clears one char from the pending prefix" do
      expect(on_keydown_body).to match(
        /event\.key\s*===\s*"Backspace"/
      )
      expect(on_keydown_body).to match(
        /this\.pendingPrefix\s*=\s*this\.pendingPrefix\.slice\(\s*0\s*,\s*-1\s*\)/
      )
    end

    it "Backspace on an empty prefix falls back to popMenu()" do
      # The legacy submenu pop-back still works for any future schema
      # that ships a nested menu — when prefix is empty, Backspace
      # navigates back one level.
      expect(on_keydown_body).to match(
        /if\s*\(\s*this\.pendingPrefix\.length\s*>\s*0\s*\)[\s\S]*?else\s*\{[\s\S]*?this\.popMenu\(\)/m
      )
    end

    it "A3: Space toggles — closes the popup when open" do
      expect(on_keydown_body).to match(
        /event\.key\s*===\s*" "\s*\)[\s\S]*?event\.preventDefault\(\)[\s\S]*?this\.close\(\)/m
      )
    end

    it "Space opens the root menu when closed (popup-closed path)" do
      expect(on_keydown_body).to match(/this\.openMenu\(\s*"root"\s*\)/)
    end

    it "Space defers to keyboard-row selection when a row is highlighted" do
      # When a `[data-keyboard-row]` carries `.keyboard-highlight`,
      # the keyboard controller owns SPACE (toggle row selection); the
      # leader popup must not open.
      expect(on_keydown_body).to match(
        /\[data-keyboard-row\]\.keyboard-highlight/
      )
    end

    it "routes a single-char keystroke through handlePrefixKey when the popup is open" do
      expect(on_keydown_body).to match(
        /event\.key\.length\s*===\s*1/
      )
      expect(on_keydown_body).to match(
        /this\.handlePrefixKey\(\s*event\.key\s*\)/
      )
    end
  end

  describe "handlePrefixKey — 2-key sequence accumulator" do
    let(:handle_prefix_body) do
      controller_source[/handlePrefixKey\s*\(\s*key\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "appends the keystroke to `pendingPrefix`" do
      expect(handle_prefix_body).to match(/this\.pendingPrefix\s*\+=\s*key/)
    end

    it "fires unique exact matches immediately (no longer-prefix candidates)" do
      expect(handle_prefix_body).to match(/exact\s*&&\s*!longer/)
      expect(handle_prefix_body).to match(/this\.activate\(\s*itemToFire\s*\)/)
    end

    it "stashes the exact match for the timer when longer candidates also exist" do
      # Phase C — `d` (dark mode) on /settings must still fire after a
      # ~1500 ms grace period even though `da` / `dd` share the `d`
      # prefix.
      expect(handle_prefix_body).to match(
        /this\.pendingExactMatch\s*=\s*exact\s*\|\|\s*null/
      )
    end

    it "resets silently on a dead-end keystroke (zero candidates)" do
      expect(handle_prefix_body).to match(
        /candidates\.length\s*===\s*0[\s\S]*?this\.resetPrefix\(\)/m
      )
    end

    it "arms the inactivity timer when waiting for a follow-up key" do
      expect(handle_prefix_body).to match(/this\.armPrefixTimer\(\)/)
    end
  end

  describe "armPrefixTimer — 1500 ms inactivity reset with exact-match grace" do
    let(:arm_body) do
      controller_source[/armPrefixTimer\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "sets a 1500 ms timeout" do
      expect(arm_body).to match(/setTimeout\([\s\S]*?,\s*1500\s*\)/)
    end

    it "clears any previously pending timer (no double-fire)" do
      expect(arm_body).to match(/clearTimeout\(\s*this\.prefixTimer\s*\)/)
    end

    it "fires the stashed exact-match candidate on expiry, if any" do
      # The snapshot via local `stashed` is the load-bearing detail —
      # resetPrefix() clears pendingExactMatch BEFORE activate would
      # otherwise see it, so the timer captures the value first.
      expect(arm_body).to match(/const\s+stashed\s*=\s*this\.pendingExactMatch/)
      expect(arm_body).to match(/if\s*\(\s*stashed\s*\)/)
      expect(arm_body).to match(/this\.activate\(\s*stashed\s*\)/)
    end
  end

  describe "resetPrefix — full teardown of the accumulator state" do
    let(:reset_body) do
      controller_source[/resetPrefix\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "clears pendingPrefix, pendingExactMatch, and the timer" do
      expect(reset_body).to match(/this\.pendingPrefix\s*=\s*""/)
      expect(reset_body).to match(/this\.pendingExactMatch\s*=\s*null/)
      expect(reset_body).to match(/clearTimeout\(\s*this\.prefixTimer\s*\)/)
      expect(reset_body).to match(/this\.prefixTimer\s*=\s*null/)
    end
  end

  describe "openRoot — toggle behavior wired to the footer `[_]` link" do
    let(:open_root_body) do
      controller_source[/openRoot\s*\(\s*event\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "closes the popup if already open (LazyVim-style double-tap)" do
      expect(open_root_body).to match(/this\.isOpen\(\)[\s\S]*?this\.close\(\)/m)
    end

    it "opens the root menu otherwise" do
      expect(open_root_body).to match(/this\.openMenu\(\s*"root"\s*\)/)
    end
  end

  describe "isOpen — reads the native <dialog> `open` attribute" do
    it "checks `this.popupTarget.open === true`" do
      # The popup IS a native <dialog> opened via .showModal() so it
      # renders in the browser top layer above other modals. The
      # `open` attribute is the live state — z-index alone can't beat
      # top-layer content (per the 2026-05-17 architectural switch).
      expect(controller_source).to match(
        /isOpen\s*\(\s*\)\s*\{[\s\S]*?this\.popupTarget\.open\s*===\s*true/m
      )
    end
  end

  describe "showPopup — top-layer mount via .showModal()" do
    let(:show_body) do
      controller_source[/showPopup\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "guards against double-open (Firefox throws InvalidStateError)" do
      expect(show_body).to match(/if\s*\(\s*this\.popupTarget\.open\s*\)\s*return/)
    end

    it "calls .showModal() to place the popup in the browser top layer" do
      expect(show_body).to match(/this\.popupTarget\.showModal\(\)/)
    end
  end

  describe "fireAction — YAML-driven dispatch table" do
    let(:fire_action_body) do
      controller_source[/fireAction\s*\(\s*item\s*,\s*action\s*,\s*\{\s*closePopup\s*\}\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "closes the popup before running the side-effect" do
      expect(fire_action_body).to match(/if\s*\(\s*closePopup\s*\)\s+this\.close\(\)/)
    end

    it "dispatches `navigate` → navigateTo(action.path)" do
      expect(fire_action_body).to match(
        /action\.type\s*===\s*"navigate"[\s\S]*?this\.navigateTo\(\s*action\.path\s*\)/m
      )
    end

    it "does NOT carry a `theme_toggle` branch (removed alongside the single-theme cleanup, 2026-05-19)" do
      # The legacy `theme_toggle` action emitted by the YAML dispatch
      # table is gone. The leader popup no longer toggles dark/light;
      # the controller should not even reference the action type.
      expect(fire_action_body).not_to match(/theme_toggle/)
      expect(fire_action_body).not_to match(/themeToggle/)
    end

    it "dispatches `page_sync` → pageSync()" do
      expect(fire_action_body).to match(
        /action\.type\s*===\s*"page_sync"[\s\S]*?this\.pageSync\(\)/m
      )
    end

    it "dispatches `page_delete` → pageDelete()" do
      expect(fire_action_body).to match(
        /action\.type\s*===\s*"page_delete"[\s\S]*?this\.pageDelete\(\)/m
      )
    end

    it "dispatches `page_add_bundle` → pageAddBundle()" do
      expect(fire_action_body).to match(
        /action\.type\s*===\s*"page_add_bundle"[\s\S]*?this\.pageAddBundle\(\)/m
      )
    end

    it "dispatches `open_modal` with modal_id=search_placeholder → openGlobalSearch()" do
      expect(fire_action_body).to match(
        /action\.type\s*===\s*"open_modal"\s*&&\s*action\.modal_id\s*===\s*"search_placeholder"[\s\S]*?this\.openGlobalSearch\(\)/m
      )
    end

    it "dispatches `toggle_filter_chip` → toggleFilterChip(action.token)" do
      expect(fire_action_body).to match(
        /action\.type\s*===\s*"toggle_filter_chip"[\s\S]*?this\.toggleFilterChip\(\s*action\.token\s*\)/m
      )
    end

    it "dispatches `logout` → performLogout()" do
      expect(fire_action_body).to match(
        /action\.type\s*===\s*"logout"[\s\S]*?this\.performLogout\(\)/m
      )
    end

    it "dispatches `trigger_inline_edit` → triggerInlineEdit(action.target)" do
      expect(fire_action_body).to match(
        /action\.type\s*===\s*"trigger_inline_edit"[\s\S]*?this\.triggerInlineEdit\(\s*action\.target\s*\)/m
      )
    end

    it "dispatches `submit_confirm_modal` → submitConfirmModal()" do
      expect(fire_action_body).to match(
        /action\.type\s*===\s*"submit_confirm_modal"[\s\S]*?this\.submitConfirmModal\(\)/m
      )
    end

    it "dispatches `open_modal_by_id` → openModalById(action.target)" do
      expect(fire_action_body).to match(
        /action\.type\s*===\s*"open_modal_by_id"[\s\S]*?this\.openModalById\(\s*action\.target\s*\)/m
      )
    end

    it "dispatches `open_revoke_unused_modal` → openRevokeUnusedModal(action.target)" do
      expect(fire_action_body).to match(
        /action\.type\s*===\s*"open_revoke_unused_modal"[\s\S]*?this\.openRevokeUnusedModal\(\s*action\.target\s*\)/m
      )
    end

    it "dispatches `toggle_setting` → toggleSetting(action.target)" do
      expect(fire_action_body).to match(
        /action\.type\s*===\s*"toggle_setting"[\s\S]*?this\.toggleSetting\(\s*action\.target\s*\)/m
      )
    end

    it "falls through to a `leader-menu:action` CustomEvent for unknown action types" do
      # Forward-compat: future action types plug in via the
      # CustomEvent without touching this controller.
      expect(fire_action_body).to match(
        /new\s+CustomEvent\(\s*"leader-menu:action"/
      )
    end
  end

  describe "named action handlers — themeToggle removed (2026-05-19)" do
    it "does not define a themeToggle() handler on the controller" do
      # The single-theme cleanup deleted the theme system; the named
      # handler the dispatch table used to call is gone.
      expect(controller_source).not_to match(/themeToggle\s*\(\s*\)\s*\{/)
    end

    it "does not reference the localStorage `pito-theme` key" do
      expect(controller_source).not_to match(/pito-theme/)
    end

    it "does not call window.recolorCharts (no theme flip to recolor for)" do
      expect(controller_source).not_to match(/recolorCharts/)
    end
  end

  describe "named action handlers — pageSync / pageDelete / pageAddBundle" do
    it "pageSync() clicks the breadcrumb [data-page-action=sync] hook" do
      page_sync_body = controller_source[/pageSync\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(page_sync_body).to match(/\[data-page-action="sync"\]/)
      expect(page_sync_body).to match(/el\.click\(\)/)
    end

    it "pageDelete() clicks the breadcrumb [data-page-action=delete] hook" do
      page_delete_body = controller_source[/pageDelete\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(page_delete_body).to match(/\[data-page-action="delete"\]/)
      expect(page_delete_body).to match(/el\.click\(\)/)
    end

    it "pageAddBundle() clicks the [+] create hook on /games" do
      page_add_body = controller_source[/pageAddBundle\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(page_add_body).to match(/\[data-page-action="add-bundle"\]/)
      expect(page_add_body).to match(/el\.click\(\)/)
    end
  end

  describe "named action handlers — openModalById" do
    let(:open_modal_body) do
      controller_source[/openModalById\s*\(\s*targetId\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "looks the dialog up via getElementById and bails when missing" do
      expect(open_modal_body).to match(
        /document\.getElementById\(\s*targetId\s*\)/
      )
      expect(open_modal_body).to match(/if\s*\(\s*!dlg\s*\)\s*return/)
    end

    it "guards against non-<dialog> elements (no .showModal function)" do
      expect(open_modal_body).to match(
        /typeof\s+dlg\.showModal\s*!==\s*"function"/
      )
    end

    it "guards against re-opening an already-open dialog (Firefox InvalidStateError)" do
      expect(open_modal_body).to match(/if\s*\(\s*dlg\.open\s*\)\s*return/)
    end

    it "calls .showModal() to place the dialog in the top layer" do
      expect(open_modal_body).to match(/dlg\.showModal\(\)/)
    end
  end

  describe "named action handlers — openGlobalSearch" do
    let(:global_search_body) do
      controller_source[/openGlobalSearch\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "looks the `global-search-modal` <dialog> up and resolves its controller" do
      expect(global_search_body).to match(
        /document\.getElementById\(\s*"global-search-modal"\s*\)/
      )
      expect(global_search_body).to match(
        /getControllerForElementAndIdentifier\(\s*dialog\s*,\s*"global-search-modal"\s*\)/
      )
    end

    it "calls ctrl.open() when the controller resolves; otherwise falls back to native .showModal()" do
      expect(global_search_body).to match(/ctrl\.open\(\)/)
      expect(global_search_body).to match(/dialog\.showModal\(\)/)
    end
  end

  describe "named action handlers — toggleFilterChip" do
    let(:toggle_chip_body) do
      controller_source[/toggleFilterChip\s*\(\s*token\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "delegates to the chip's existing click handler so the cascade runs through games_filter_controller" do
      expect(toggle_chip_body).to match(
        /\[data-filter-token="\$\{token\}"\]/
      )
      expect(toggle_chip_body).to match(/chip\.click\(\)/)
    end
  end

  describe "named action handlers — performLogout" do
    let(:logout_body) do
      controller_source[/performLogout\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "builds a hidden DELETE form for /session with the CSRF token" do
      expect(logout_body).to match(/form\.action\s*=\s*"\/session"/)
      expect(logout_body).to match(/methodInput\.value\s*=\s*"delete"/)
      expect(logout_body).to match(/meta\[name="csrf-token"\]/)
      expect(logout_body).to match(/csrfInput\.name\s*=\s*"authenticity_token"/)
    end

    it "submits the form so Rails routes to Sessions#destroy" do
      expect(logout_body).to match(/form\.submit\(\)/)
    end
  end

  describe "navigateTo — Turbo.visit with a window.location fallback" do
    let(:navigate_body) do
      controller_source[/navigateTo\s*\(\s*path\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "prefers Turbo.visit when available" do
      expect(navigate_body).to match(/window\.Turbo\.visit\(\s*path\s*\)/)
    end

    it "falls back to window.location.assign(path)" do
      expect(navigate_body).to match(/window\.location\.assign\(\s*path\s*\)/)
    end
  end

  describe "submenu defensive branch" do
    it "still handles a row carrying `submenu` even though the shipped schema is flat" do
      # 2026-05-18: root menus are flat 2-key dispatch — no shipped
      # row carries `submenu`. The defensive branch stays so any
      # future schema entry that opts back in still works without a
      # code change here.
      activate_body = controller_source[/activate\s*\(\s*item\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(activate_body).to match(/hasSubmenu\s*=\s*!!item\.submenu/)
      expect(activate_body).to match(/this\.openMenu\(\s*item\.submenu\s*\)/)
    end

    it "handles inline submenus (`type: submenu` + items array) on page-action items" do
      # The `f filter` submenu on /games is an inline submenu —
      # action: { type: submenu, items: [...] }.
      activate_body = controller_source[/activate\s*\(\s*item\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(activate_body).to match(
        /action\.type\s*===\s*"submenu"\s*&&\s*Array\.isArray\(\s*action\.items\s*\)/
      )
      expect(activate_body).to match(/this\.inlineMenus\[\s*inlineName\s*\]\s*=/)
    end
  end

  describe "isEditableTarget — form-control pass-through" do
    let(:editable_body) do
      controller_source[/isEditableTarget\s*\(\s*target\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "matches input, textarea, select, button, and [contenteditable]" do
      # The skip set is what makes /settings (dense with form controls)
      # usable. <a> is intentionally OUT of the set so the leader popup
      # still opens on SPACE while a navbar link is focused.
      expect(editable_body).to match(
        /input,\s*textarea,\s*select,\s*button,\s*\[contenteditable\]/
      )
    end
  end

  describe "resolvePageActions — modal context overrides page context" do
    let(:resolve_body) do
      controller_source[/resolvePageActions\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "reads YAML-driven page_actions via the body data attribute" do
      expect(resolve_body).to match(/document\.body\?\.dataset\?\.keybindingsPageKey/)
      expect(resolve_body).to match(/this\.schema\.page_actions\[\s*pageKey\s*\]/)
    end

    it "modal_actions take precedence when a <dialog open> carries data-modal-actions-key" do
      expect(resolve_body).to match(
        /dialog\[open\]\[data-modal-actions-key\]/
      )
      expect(resolve_body).to match(/this\.schema\.modal_actions/)
    end

    it "falls back to the `default` page_actions entry when no page key matches" do
      expect(resolve_body).to match(
        /this\.schema\.page_actions\["default"\]/
      )
    end
  end

  describe "sessionStorage rehydrate / persistStack" do
    it "persists the menu stack under a module-level storage key" do
      expect(controller_source).to match(/STACK_STORAGE_KEY\s*=\s*"pito:leader-menu:stack"/)
      expect(controller_source).to match(/sessionStorage\.setItem\(\s*STACK_STORAGE_KEY/)
    end

    it "rehydrate() validates every entry against menuByName before trusting the stack" do
      # A stale stack referencing a removed menu name would otherwise
      # render an empty popup; the validation invalidates the cache
      # and returns silently.
      rehydrate_body = controller_source[/rehydrate\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(rehydrate_body).to match(
        /stack\.every\(\s*\(\s*name\s*\)\s*=>\s*!!this\.menuByName\(\s*name\s*\)\s*\)/
      )
    end
  end
end
