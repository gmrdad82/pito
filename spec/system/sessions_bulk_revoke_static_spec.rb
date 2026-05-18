require "rails_helper"

# Static-source structural lock for the `sessions-bulk-revoke` Stimulus
# controller
# (`app/javascript/controllers/sessions_bulk_revoke_controller.js`).
#
# Rack_test has no JS engine, so the runtime modal-populate-then-open
# flow (and the live `[revoke N]` link mutation that accompanies
# checkbox flips) can't be exercised directly via Capybara. What we
# CAN lock is the source text of the controller — target declarations,
# handler names, the action-URL `0` → joined-ids rewrite, the CSRF
# refresh hook, and the toolbar `[revoke]` ↔ `[revoke N]` class flip.
# Catches refactor breakage where someone renames a target, drops the
# CSRF refresh path, or silently changes the URL-mutation regex.
RSpec.describe "SessionsBulkRevoke Stimulus controller (static source)", type: :system do
  before { driven_by(:rack_test) }

  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/sessions_bulk_revoke_controller.js")
    )
  end

  describe "controller declaration" do
    it "exports a default Stimulus Controller subclass" do
      expect(controller_source).to match(
        /export\s+default\s+class\s+extends\s+Controller/
      )
    end

    it "declares the full target set required by the modal-confirm flow" do
      # `modal`, `modalTitle`, `modalWarning`, `modalForm` are the four
      # populate-on-click targets; `link`, `headerCheckbox`, `checkbox`
      # drive the toolbar + selection state. All seven must stay
      # declared — dropping any breaks either the populate step or the
      # selection round-trip.
      expect(controller_source).to match(/static\s+targets\s*=\s*\[[^\]]*"link"/m)
      expect(controller_source).to match(/static\s+targets\s*=\s*\[[^\]]*"headerCheckbox"/m)
      expect(controller_source).to match(/static\s+targets\s*=\s*\[[^\]]*"checkbox"/m)
      expect(controller_source).to match(/static\s+targets\s*=\s*\[[^\]]*"modal"/m)
      expect(controller_source).to match(/static\s+targets\s*=\s*\[[^\]]*"modalTitle"/m)
      expect(controller_source).to match(/static\s+targets\s*=\s*\[[^\]]*"modalWarning"/m)
      expect(controller_source).to match(/static\s+targets\s*=\s*\[[^\]]*"modalForm"/m)
    end
  end

  describe "checkbox change handlers" do
    it "defines toggle() and toggleAll() handlers for row + header changes" do
      # `toggle()` fires on every row checkbox change; `toggleAll()`
      # fires on the header checkbox change. Both eventually call
      # `update()` so the `[revoke N]` link and header state recompute.
      expect(controller_source).to match(/^\s*toggle\(\s*\)\s*\{/m)
      expect(controller_source).to match(/^\s*toggleAll\(\s*\)\s*\{/m)
    end

    it "calls update() from connect() so the initial render reflects state" do
      # The initial `[revoke]` ↔ `[revoke N]` paint runs once on connect
      # so a server-rendered selection (none today, but defensive) lands
      # in the right visual state.
      expect(controller_source).to match(/connect\(\s*\)\s*\{[^}]*this\.update\(\)/m)
    end
  end

  describe "toolbar enable/disable logic" do
    it "flips the link between `[revoke]` (muted) and `[revoke N]` (danger)" do
      # The idle state uses the `bracketed-muted` class with the literal
      # `[revoke]` label; the active state adds `bracketed` + `text-danger`
      # and surfaces the live count.
      expect(controller_source).to include('link.classList.add("bracketed-muted")')
      expect(controller_source).to include('link.textContent = "[revoke]"')
      expect(controller_source).to include('link.classList.remove("bracketed-muted")')
      expect(controller_source).to include('link.classList.add("bracketed", "text-danger")')
    end

    it "wires the active-state click to sessions-bulk-revoke#open" do
      # The active `[revoke N]` link does NOT navigate — clicking it
      # opens the confirm modal via the controller's own `open` action.
      expect(controller_source).to include(
        'link.setAttribute("data-action", "click->sessions-bulk-revoke#open")'
      )
    end
  end

  describe "modal action-URL rewrite (0 → joined ids)" do
    it "swaps the placeholder ids segment with the comma-joined selection" do
      # The form's `action` attribute carries a literal `0` ids segment
      # at render time (route constraint requires a digit); on click we
      # swap the trailing `[\d,]+` segment with the joined id list. Lock
      # the literal regex pattern + replacement template via substring
      # checks so a refactor that changes the URL shape catches.
      expect(controller_source).to include('/\/revokes\/[\d,]+\b/')
      expect(controller_source).to include('`/revokes/${ids.join(",")}`')
    end

    it "writes the rewritten action back via setAttribute" do
      expect(controller_source).to match(/form\.setAttribute\(\s*"action"\s*,\s*next\s*\)/)
    end
  end

  describe "CSRF refresh hook" do
    it "defines the refreshCsrf(event) handler" do
      # The hook is wired via `data-action="submit->sessions-bulk-revoke#refreshCsrf"`
      # on the modal form so the freshest CSRF token gets copied from
      # `<meta name="csrf-token">` into the form's hidden input
      # immediately before the native POST fires.
      expect(controller_source).to match(/refreshCsrf\s*\(\s*event\s*\)\s*\{/)
    end

    it "reads the live CSRF token from the meta tag" do
      expect(controller_source).to include('meta[name="csrf-token"]')
      expect(controller_source).to match(/meta\.getAttribute\(\s*"content"\s*\)/)
    end

    it "writes the fresh token into the form's authenticity_token input" do
      expect(controller_source).to include('input[name="authenticity_token"]')
      expect(controller_source).to match(/tokenInput\.value\s*=\s*fresh/)
    end
  end

  describe "modal populate-then-open flow" do
    it "populates the modal then calls showModal() inside open()" do
      # The click handler MUST populate the title / warning / form
      # action BEFORE opening the modal so the dialog never flashes the
      # placeholder text or the literal `0` ids segment to the user.
      expect(controller_source).to match(
        /open\([^}]*this\.populateModal\(ids\)[^}]*this\.modalTarget\.showModal\(\)/m
      )
    end

    it "detects current-session-in-selection via data-current=yes" do
      # The conditional warning line is hidden unless at least one
      # checked row carries `data-current="yes"` (only the row matching
      # the active session does in the template).
      expect(controller_source).to match(/cb\.dataset\.current\s*===\s*"yes"/)
    end
  end
end
