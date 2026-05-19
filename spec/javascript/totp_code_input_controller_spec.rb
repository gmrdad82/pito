require "rails_helper"

# 2026-05-18 — Static-source structural lock for the
# `totp-code-input` Stimulus controller
# (`app/javascript/controllers/totp_code_input_controller.js`).
#
# Rack_test has no JS engine, so the runtime distribute / auto-submit
# behavior can't be exercised directly via Capybara. What we CAN lock
# is the source text of the controller — handler names, target
# declarations, and the specific behaviors that fix the two MUST-WORK
# scenarios behind the 2026-05-18 dispatch:
#
#   1. 1Password / browser-extension autofill that shoves the full
#      6-digit code into ONE box as a single `input` event with
#      `value.length > 1` — the controller must distribute the chars
#      across cells starting at the cell that received the input.
#   2. Auto-submit on the 6th digit, regardless of how the digits
#      arrived (typing, paste, autofill) — the controller must call
#      `form.requestSubmit()` once all six cells carry a digit.
#
# A future refactor that drops either behavior breaks this spec
# loudly, which is the entire point.
RSpec.describe "totp_code_input_controller.js" do
  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/totp_code_input_controller.js")
    )
  end

  describe "controller declaration" do
    it "exports a default Stimulus Controller subclass" do
      expect(controller_source).to match(
        /export\s+default\s+class\s+extends\s+Controller/
      )
    end

    it "declares `digit` and `hidden` as Stimulus targets" do
      expect(controller_source).to match(
        /static\s+targets\s*=\s*\[\s*"digit"\s*,\s*"hidden"\s*\]/
      )
    end
  end

  describe "onInput handler — manual single-digit entry" do
    it "defines the onInput(event) handler" do
      expect(controller_source).to match(/onInput\s*\(\s*event\s*\)\s*\{/)
    end

    it "strips non-digits from the input value" do
      expect(controller_source).to match(/replace\(\s*\/\\D\/g\s*,\s*""\s*\)/)
    end

    it "advances focus to the next cell after a successful single digit" do
      # The single-digit branch picks up `cells[idx + 1].focus()` style
      # advancement via the `digitTargets[idx + 1].focus()` call.
      expect(controller_source).to match(
        /this\.digitTargets\[\s*idx\s*\+\s*1\s*\]\.focus\(\)/
      )
    end
  end

  describe "onInput handler — multi-char autofill distribution" do
    it "branches on `cleaned.length <= 1` vs multi-char payload" do
      # The branch is the gate that lets 1Password autofill (a single
      # `input` event with the full 6-digit string) trigger the
      # distribute path instead of being silently truncated to one
      # digit via `slice(-1)`.
      expect(controller_source).to match(/cleaned\.length\s*<=\s*1/)
    end

    it "delegates multi-char distribution to `_distributeFrom(idx, cleaned)`" do
      # The autofill case must hand off to the same private helper
      # that the paste handler uses so both paths behave identically.
      expect(controller_source).to match(
        /this\._distributeFrom\(\s*idx\s*,\s*cleaned\s*\)/
      )
    end
  end

  describe "onPaste handler — distribute from the focused cell" do
    it "defines the onPaste(event) handler" do
      expect(controller_source).to match(/onPaste\s*\(\s*event\s*\)\s*\{/)
    end

    it "preventDefaults so the browser does not double-write the paste payload" do
      expect(controller_source).to match(
        /onPaste\s*\([^}]*event\.preventDefault\(\)/m
      )
    end

    it "reads the paste payload from clipboardData (with the IE fallback)" do
      expect(controller_source).to match(/event\.clipboardData/)
      expect(controller_source).to match(/window\.clipboardData/)
      expect(controller_source).to match(/getData\(\s*"text"\s*\)/)
    end

    it "strips non-digits from the pasted payload" do
      # The paste handler must run `\D` stripping just like the input
      # handler so a "123 456" or "123-456" clipboard string still
      # fills the six cells correctly. Match the literal call inside
      # the onPaste method body — assert the controller source contains
      # the call AND that it sits between the onPaste declaration and
      # the next method declaration (_distributeFrom).
      paste_to_next = controller_source[/onPaste\s*\([\s\S]*?(?=^\s{2}_distributeFrom)/m].to_s
      expect(paste_to_next).to match(/replace\(\s*\/\\D\/g\s*,\s*""\s*\)/),
        "expected onPaste to strip non-digits via .replace(/\\D/g, '')"
    end

    it "distributes starting at the pasted-into cell, not always from index 0" do
      # The fix: a paste into box 3 must fill cells 3..5, not boxes
      # 0..2. The handler computes `startAt` from
      # `digitTargets.indexOf(event.target)` and passes it to
      # `_distributeFrom(startAt, cleaned)`. Lock both halves.
      expect(controller_source).to match(
        /this\.digitTargets\.indexOf\(\s*event\.target\s*\)/
      )
      expect(controller_source).to match(
        /this\._distributeFrom\(\s*startAt\s*,\s*cleaned\s*\)/
      )
    end
  end

  describe "_distributeFrom private helper" do
    it "is defined as a `_distributeFrom(startIdx, digits)` method" do
      expect(controller_source).to match(
        /_distributeFrom\s*\(\s*startIdx\s*,\s*digits\s*\)\s*\{/
      )
    end

    it "limits the write count to whichever runs out first — digits or remaining cells" do
      # The cells-remaining clamp prevents a 6-char paste into cell 3
      # from running off the end of the digitTargets array.
      expect(controller_source).to match(
        /Math\.min\(\s*digits\.length\s*,\s*cells\.length\s*-\s*startIdx\s*\)/
      )
    end

    it "writes `digits[i]` into `cells[startIdx + i]` in a loop" do
      expect(controller_source).to match(
        /cells\[\s*startIdx\s*\+\s*i\s*\]\.value\s*=\s*digits\[\s*i\s*\]/
      )
    end

    it "focuses the cell after the last filled one" do
      expect(controller_source).to match(/cells\[next\]\?\.focus\(\)/)
    end
  end

  describe "auto-submit on the 6th digit" do
    it "is defined as a `_maybeAutoSubmit()` private helper" do
      expect(controller_source).to match(/_maybeAutoSubmit\s*\(\s*\)\s*\{/)
    end

    it "is invoked from BOTH the onInput and onPaste paths" do
      # Autofill arrives via `input`; paste arrives via `paste`. Both
      # must fire the auto-submit check so a 6-digit landing on ANY
      # input path triggers the submit. Match the method blocks by
      # slicing between method declarations rather than relying on
      # brace matching across multi-line bodies.
      on_input = controller_source[/onInput\s*\([\s\S]*?(?=^\s{2}onKeydown)/m].to_s
      on_paste = controller_source[/onPaste\s*\([\s\S]*?(?=^\s{2}_distributeFrom)/m].to_s
      expect(on_input).to include("this._maybeAutoSubmit()"),
        "expected onInput to call this._maybeAutoSubmit()"
      expect(on_paste).to include("this._maybeAutoSubmit()"),
        "expected onPaste to call this._maybeAutoSubmit()"
    end

    it "gates on a full-length all-digit code" do
      # The submit only fires when EVERY cell carries a digit. The
      # helper compares the concatenated length against
      # `this.digitTargets.length` and re-checks the all-digit shape.
      expect(controller_source).to match(
        /code\.length\s*!==\s*this\.digitTargets\.length/
      )
      expect(controller_source).to match(%r{/\^\\d\+\$/\.test\(\s*code\s*\)})
    end

    it "submits via form.requestSubmit() when available" do
      # `requestSubmit()` fires the form's submit-event listeners
      # (Turbo, our own interceptors). `form.submit()` bypasses them
      # and is the fallback for ancient browsers.
      expect(controller_source).to match(
        /typeof\s+form\.requestSubmit\s*===\s*"function"/
      )
      expect(controller_source).to match(/form\.requestSubmit\(\)/)
      expect(controller_source).to match(/form\.submit\(\)/)
    end

    it "looks the form up via `this.element.closest('form')`" do
      # The controller is mounted on the wrapper `<div>` inside the
      # form. closest('form') is the right traversal — it returns
      # null if the component is ever rendered outside a form, in
      # which case the helper bails without submitting.
      expect(controller_source).to match(
        /this\.element\.closest\(\s*"form"\s*\)/
      )
    end

    it "guards against double-submit via a `_submitted` flag" do
      # A second `input` / `paste` event firing while the navigation
      # is in flight must NOT trigger a second POST. The flag is set
      # the first time the form is submitted and never reset until
      # the controller reconnects on a fresh page.
      expect(controller_source).to match(/this\._submitted\s*=\s*false/)
      expect(controller_source).to match(/if\s*\(\s*this\._submitted\s*\)\s*return/)
      expect(controller_source).to match(/this\._submitted\s*=\s*true/)
    end
  end

  describe "backspace navigation" do
    it "steps focus back when backspace lands on an empty cell" do
      # The empty-cell branch checks `!box.value && idx > 0` then
      # focuses the previous cell. Don't break this — losing it makes
      # the segmented input feel broken to keyboard-only users.
      expect(controller_source).to match(
        /event\.key\s*===\s*"Backspace"\s*&&\s*!box\.value\s*&&\s*idx\s*>\s*0/
      )
    end
  end

  describe "hidden field sync" do
    it "rewrites the hidden target's value on every change" do
      expect(controller_source).to match(/_syncHidden\s*\(\s*\)\s*\{/)
      expect(controller_source).to match(
        /this\.hiddenTarget\.value\s*=\s*this\.digitTargets/
      )
    end
  end

  # 2026-05-18 (layered autofill catch) — 1Password / Brave's native
  # `autocomplete="one-time-code"` autofill can bypass the `input`
  # event by writing through the HTMLInputElement value setter. To
  # catch every variant we layer three additional listeners:
  #
  #   - `change` on each cell — delegated to the existing `onInput`
  #     handler because the autofill payload follows the same shape
  #     (single digit OR full multi-char string) as a manual / paste
  #     event.
  #   - `blur` on each cell — invokes a NEW `onCellBlur` handler that
  #     defensively syncs the hidden field and re-checks auto-submit.
  #   - `submit` (capture phase) on the parent form — registered in
  #     `connect()` and torn down in `disconnect()` so a silent
  #     autofill that submits the form WITHOUT firing input/change/blur
  #     still lands the right concatenated value on the wire.
  #
  # Each assertion below locks one of the three layers. Static-source
  # style: regex against the controller file.
  describe "autofill layered catch — `change` event delegated to onInput" do
    it "is referenced in the controller source as a wired surface" do
      # The component template wires `change->totp-code-input#onInput`
      # on each cell; the controller source must explicitly document
      # the `change` event in its leading comment so a future reader
      # knows why the existing onInput method handles it.
      expect(controller_source).to match(/\bchange\b/)
    end
  end

  describe "autofill layered catch — `blur` event invokes onCellBlur" do
    it "defines the onCellBlur() handler" do
      expect(controller_source).to match(/onCellBlur\s*\(\s*\)\s*\{/)
    end

    it "calls _syncHidden() and _maybeAutoSubmit() from onCellBlur" do
      # Slice the onCellBlur method body and assert it carries both
      # calls. We deliberately do NOT redistribute on blur — that
      # would interfere with Tab / Shift+Tab navigation from a half-
      # filled cell.
      on_cell_blur = controller_source[/onCellBlur\s*\([\s\S]*?\n\s{2}\}/m].to_s
      expect(on_cell_blur).to include("this._syncHidden()"),
        "expected onCellBlur to call this._syncHidden()"
      expect(on_cell_blur).to include("this._maybeAutoSubmit()"),
        "expected onCellBlur to call this._maybeAutoSubmit()"
    end

    it "does NOT redistribute digits on blur" do
      # Tab navigation from a half-filled cell must not shove digits
      # around. The blur handler is read-only over the cells.
      on_cell_blur = controller_source[/onCellBlur\s*\([\s\S]*?\n\s{2}\}/m].to_s
      expect(on_cell_blur).not_to include("_distributeFrom"),
        "onCellBlur must not call _distributeFrom — that would " \
        "interfere with Tab navigation from a half-filled cell"
    end
  end

  describe "autofill layered catch — capture-phase form submit listener" do
    it "registers a `submit` listener on the parent form in connect()" do
      # connect() must look the form up via closest('form') and add a
      # capture-phase submit listener that defensively syncs the
      # hidden field before Turbo's own listener runs.
      connect_body = controller_source[/connect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(connect_body).to include('this.element.closest("form")'),
        "expected connect() to look the form up via closest('form')"
      expect(connect_body).to match(
        /addEventListener\(\s*"submit"\s*,\s*this\._onFormSubmit\s*,\s*true\s*\)/
      ),
        "expected connect() to addEventListener('submit', ..., true) " \
        "with capture=true so it runs BEFORE Turbo's own listener"
    end

    it "stores the form and handler references on the instance for teardown" do
      # The capture-phase listener must be removable with the EXACT
      # same function reference, which means the bound handler has
      # to be cached on the instance (`this._onFormSubmit`) rather
      # than created inline on each call.
      expect(controller_source).to match(/this\._form\s*=\s*this\.element\.closest/)
      expect(controller_source).to match(/this\._onFormSubmit\s*=/)
    end

    it "calls _syncHidden() from the cached submit handler" do
      # The handler body must run _syncHidden so a silent-autofill +
      # form-submit path lands the right concatenated value on the
      # wire even when no per-cell event ever fired.
      expect(controller_source).to match(
        /this\._onFormSubmit\s*=\s*\(\s*\)\s*=>\s*this\._syncHidden\(\)/
      )
    end

    it "tears the submit listener down in disconnect()" do
      # Turbo morphs and controller re-mounts must not leak duplicate
      # capture-phase listeners. disconnect() removes the same
      # function reference it added, with the same capture=true flag.
      disconnect_body = controller_source[/disconnect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(disconnect_body).to include(
        "removeEventListener"
      ), "expected disconnect() to call removeEventListener"
      expect(disconnect_body).to match(
        /removeEventListener\(\s*"submit"\s*,\s*this\._onFormSubmit\s*,\s*true\s*\)/
      ),
        "expected disconnect() to remove the SAME submit handler " \
        "reference with capture=true"
    end

    it "nulls the cached references in disconnect() so a re-mount starts clean" do
      disconnect_body = controller_source[/disconnect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(disconnect_body).to match(/this\._form\s*=\s*null/)
      expect(disconnect_body).to match(/this\._onFormSubmit\s*=\s*null/)
    end
  end
end
