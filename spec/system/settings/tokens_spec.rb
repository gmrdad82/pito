require "rails_helper"

# Feature spec covering the Settings → Tokens flow end-to-end. Uses the
# default rack_test driver (no JS) — sufficient for the bracketed-link
# navigation we ship in this phase. The flow mirrors the manual playbook
# steps 4–7 + 11 from the spec.
RSpec.describe "Settings tokens flow", type: :system do
  # selenium-webdriver isn't part of the project's Gemfile (no JS-driven
  # browser specs land in this phase). The rack_test driver is sufficient
  # for the bracketed-link / form-submit flow exercised here.
  before do
    driven_by(:rack_test)
  end

  let(:user) { User.first || create(:user, tenant: Current.tenant) }

  before do
    Current.user = user
  end

  it "navigates to tokens, mints one, sees plaintext once, lands on the list" do
    visit settings_path
    expect(page).to have_content("tokens")
    click_link "manage tokens"

    expect(page).to have_current_path(settings_tokens_path)
    expect(page).to have_content("no tokens yet")

    click_link "new token"
    expect(page).to have_current_path(new_settings_token_path)

    fill_in "token[name]", with: "feature-spec-token"
    check Scopes::DEV_READ
    check Scopes::YT_READ
    click_button "[create]"

    # Plaintext-once page.
    expect(page).to have_content("token created")
    expect(page).to have_content("save this now")
    expect(page).to have_content("feature-spec-token")
    plaintext_node = find("pre code")
    plaintext = plaintext_node.text
    expect(plaintext).to match(/\A[A-Za-z0-9_\-]{40,}\z/)

    click_link "I have saved it"
    expect(page).to have_current_path(settings_tokens_path)
    expect(page).to have_content("feature-spec-token")
    # Plaintext is gone forever from the list.
    expect(page).not_to have_content(plaintext)
    # The last 4 chars are visible as the preview.
    expect(page).to have_content("...#{plaintext.last(4)}")
  end

  it "revokes a token via the action confirmation flow (no JS confirm)" do
    record, = ApiToken.generate!(
      tenant: Current.tenant, user: user,
      name: "to-be-revoked", scopes: [ Scopes::DEV_READ ]
    )

    visit settings_tokens_path
    expect(page).to have_content("to-be-revoked")

    click_link "revoke", match: :first
    expect(page).to have_current_path(revoke_settings_token_path(record))
    expect(page).to have_content("revoke token")
    expect(page).to have_content("to-be-revoked")

    click_button "[revoke]"

    expect(page).to have_current_path(settings_tokens_path)
    expect(page).to have_content("token revoked.")
    expect(record.reload.revoked_at).to be_present
  end
end
