require "rails_helper"

RSpec.describe TotpCodeInputComponent, type: :component do
  describe "structural defaults (field: :code, autofocus: true)" do
    before { render_inline(described_class.new) }

    it "renders exactly six visible digit inputs" do
      expect(page).to have_css(
        'input[data-totp-code-input-target="digit"]',
        count: 6, visible: :all
      )
    end

    it "puts maxlength=1 on every digit input" do
      expect(page).to have_css(
        'input[data-totp-code-input-target="digit"][maxlength="1"]',
        count: 6, visible: :all
      )
    end

    it "puts inputmode=numeric on every digit input" do
      expect(page).to have_css(
        'input[data-totp-code-input-target="digit"][inputmode="numeric"]',
        count: 6, visible: :all
      )
    end

    it "puts pattern='\\d{1}' on every digit input" do
      # Capybara CSS attribute selectors choke on a backslash in `\d`,
      # so assert the pattern via XPath. Six matches expected — one
      # per digit cell.
      expect(page).to have_xpath(
        '//input[@data-totp-code-input-target="digit" and @pattern="\d{1}"]',
        count: 6, visible: :all
      )
    end

    it "puts autocomplete='one-time-code' on the FIRST digit input only" do
      # Only the leftmost cell carries the OTP autocomplete token so
      # OS-level SMS / authenticator autofill targets a single field.
      expect(page).to have_css(
        'input[data-totp-code-input-target="digit"][autocomplete="one-time-code"]',
        count: 1, visible: :all
      )
    end

    it "puts autocomplete='off' on the remaining five digit inputs" do
      expect(page).to have_css(
        'input[data-totp-code-input-target="digit"][autocomplete="off"]',
        count: 5, visible: :all
      )
    end

    it "tags the first digit input as autofocus when autofocus: true (default)" do
      expect(page).to have_css(
        'input[data-totp-code-input-target="digit"][autofocus]',
        count: 1, visible: :all
      )
    end

    it "mounts the totp-code-input Stimulus controller on the wrapper" do
      expect(page).to have_css(
        'div[data-controller="totp-code-input"]', visible: :all
      )
    end

    it "wires per-box paste/input/keydown actions to the controller" do
      expect(page).to have_css(
        'input[data-totp-code-input-target="digit"]' \
        '[data-action="input->totp-code-input#onInput keydown->totp-code-input#onKeydown paste->totp-code-input#onPaste"]',
        count: 6, visible: :all
      )
    end

    it "renders a single hidden field named `code` for the concatenated value" do
      # The hidden field is the ONE element that actually carries the
      # form param the backend reads (`params[:code]`). Both
      # consumers (`Login::TotpChallengesController#create` and
      # `Settings::Security::TotpsController#create`) read this name.
      expect(page).to have_css(
        'input[type="hidden"][name="code"][data-totp-code-input-target="hidden"]',
        count: 1, visible: :all
      )
    end

    it "leaves the hidden field's initial value blank" do
      expect(page).to have_css(
        'input[type="hidden"][name="code"][value=""]', visible: :all
      )
    end

    it "does NOT name any of the visible boxes `code`" do
      # Naming the 6 visible boxes `code` would cause the form to
      # submit 6 separate `code` values, overriding the concatenated
      # hidden value. Lock the box-anonymity invariant down.
      expect(page).to have_no_css(
        'input[data-totp-code-input-target="digit"][name]',
        visible: :all
      )
    end

    it "exposes the controller's field value via a data-attribute on the wrapper" do
      expect(page).to have_css(
        'div[data-controller="totp-code-input"][data-totp-code-input-field-value="code"]',
        visible: :all
      )
    end

    it "tags each box with an aria-label (digit 1..6) for screen readers" do
      6.times do |i|
        expect(page).to have_css(
          "input[aria-label=\"digit #{i + 1}\"][data-totp-code-input-target=\"digit\"]",
          visible: :all
        )
      end
    end

    it "applies the existing .totp-modal-box / .totp-modal-boxes styling hooks" do
      # Reuses the CSS established for the layout-level TOTP
      # re-verification dialog (see `app/assets/tailwind/application.css`)
      # so the visual rhythm matches across all TOTP surfaces.
      expect(page).to have_css(
        'div.totp-modal-boxes', visible: :all
      )
      expect(page).to have_css(
        'input.totp-modal-box', count: 6, visible: :all
      )
    end
  end

  describe "with autofocus: false" do
    before { render_inline(described_class.new(autofocus: false)) }

    it "does NOT tag any input as autofocus" do
      expect(page).to have_no_css(
        'input[data-totp-code-input-target="digit"][autofocus]',
        visible: :all
      )
    end
  end

  describe "with a custom field name" do
    before { render_inline(described_class.new(field: :otp_token)) }

    it "renames the hidden field to the supplied symbol" do
      expect(page).to have_css(
        'input[type="hidden"][name="otp_token"][data-totp-code-input-target="hidden"]',
        visible: :all
      )
    end

    it "reflects the custom field name on the wrapper's data-attribute" do
      expect(page).to have_css(
        'div[data-controller="totp-code-input"][data-totp-code-input-field-value="otp_token"]',
        visible: :all
      )
    end

    it "accepts strings too (not just symbols)" do
      render_inline(described_class.new(field: "code"))
      expect(page).to have_css(
        'input[type="hidden"][name="code"]', visible: :all
      )
    end
  end
end
