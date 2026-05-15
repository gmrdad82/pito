require "rails_helper"

# Phase 12 — user account self-service. The authenticated user can
# change their own username or password. `current_password` is
# required for either mutation. No delete-account, no create-user.
#
# Phase 29 — Unit A2. The self-edit attribute is `username` (was
# `email`). The signed-in user is TOTP-configured so the mandatory-2FA
# gate does not bounce these requests to the enrollment page.
RSpec.describe "Settings::User", type: :request do
  let(:password) { "supersecret123" }
  let(:seed)     { "JBSWY3DPEHPK3PXP" }
  let(:user) do
    User.first || create(:user, password: password, password_confirmation: password)
  end
  # The signed-in user is TOTP-configured (mandatory-2FA gate), so the
  # `RecentTotpVerification` concern on the user-edit write demands a
  # fresh `totp_code` on every PATCH.
  let(:valid_code) { ROTP::TOTP.new(seed).now }

  before do |example|
    next if example.metadata[:unauthenticated]

    user.update!(
      password: password,
      password_confirmation: password,
      totp_seed_encrypted: seed,
      totp_enabled_at: 1.hour.ago,
      totp_disabled_at: nil
    )
    user.update_columns(totp_last_used_step: nil)
    sign_in_as(user)
  end

  describe "GET /settings/user" do
    it "renders the form pre-filled with the current username" do
      get settings_user_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("user")
      expect(response.body).to include(user.username)
      expect(response.body).to include("current password")
      expect(response.body).to include("new password")
    end
  end

  describe "PATCH /settings/user" do
    it "updates the username when current_password + totp_code are correct" do
      new_username = "new_#{SecureRandom.hex(4)}"

      patch settings_user_path, params: {
        user: {
          username: new_username,
          current_password: password,
          password: "",
          password_confirmation: ""
        },
        totp_code: valid_code
      }

      expect(response).to redirect_to(settings_path)
      expect(flash[:notice]).to be_present
      expect(user.reload.username).to eq(new_username)
    end

    it "updates the password when current_password and confirmation match" do
      new_password = "freshpassword456"

      patch settings_user_path, params: {
        user: {
          username: user.username,
          current_password: password,
          password: new_password,
          password_confirmation: new_password
        },
        totp_code: valid_code
      }

      expect(response).to redirect_to(settings_path)
      expect(flash[:notice]).to be_present
      expect(user.reload.authenticate(new_password)).to be_truthy
      expect(user.authenticate(password)).to be(false)
    end

    it "rejects when password and confirmation do not match" do
      original_username = user.username
      original_digest = user.password_digest

      patch settings_user_path, params: {
        user: {
          username: user.username,
          current_password: password,
          password: "freshpassword456",
          password_confirmation: "different789"
        },
        totp_code: valid_code
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("does not match")
      expect(user.reload.username).to eq(original_username)
      expect(user.password_digest).to eq(original_digest)
    end

    it "rejects when current_password is wrong and does not mutate the user" do
      original_username = user.username
      original_digest = user.password_digest

      patch settings_user_path, params: {
        user: {
          username: "should_not_stick",
          current_password: "wrong-password",
          password: "freshpassword456",
          password_confirmation: "freshpassword456"
        },
        totp_code: valid_code
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("incorrect")
      expect(user.reload.username).to eq(original_username)
      expect(user.password_digest).to eq(original_digest)
    end

    it "updates only the username when new password fields are blank" do
      new_username = "only_username_#{SecureRandom.hex(4)}"
      original_digest = user.password_digest

      patch settings_user_path, params: {
        user: {
          username: new_username,
          current_password: password,
          password: "",
          password_confirmation: ""
        },
        totp_code: valid_code
      }

      expect(response).to redirect_to(settings_path)
      expect(user.reload.username).to eq(new_username)
      expect(user.password_digest).to eq(original_digest)
    end

    it "rejects when current_password is blank" do
      original_username = user.username
      original_digest = user.password_digest

      patch settings_user_path, params: {
        user: {
          username: "blank_pw",
          current_password: "",
          password: "",
          password_confirmation: ""
        },
        totp_code: valid_code
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.username).to eq(original_username)
      expect(user.password_digest).to eq(original_digest)
    end

    it "ignores smuggled extra params (admin / role / etc.)" do
      new_username = "smuggle_#{SecureRandom.hex(4)}"

      patch settings_user_path, params: {
        user: {
          username: new_username,
          current_password: password,
          password: "",
          password_confirmation: "",
          admin: true,
          role: "owner",
          password_digest: "stolen"
        },
        totp_code: valid_code
      }

      expect(response).to redirect_to(settings_path)
      user.reload
      expect(user.username).to eq(new_username)
      # The User model has no admin/role columns, so the extra params
      # are inert by schema. The password_digest must not have been
      # rewritten by the smuggled key — verify by re-authenticating
      # against the original password.
      expect(user.authenticate(password)).to be_truthy
    end

    it "re-renders the form when username validation fails" do
      original_username = user.username

      patch settings_user_path, params: {
        user: {
          username: "not a username",
          current_password: password,
          password: "",
          password_confirmation: ""
        },
        totp_code: valid_code
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.username).to eq(original_username)
    end
  end

  # 2026-05-11 polish (Fix 4) — TOTP modal adoption.
  #
  # The user-edit form used to render an inline `<input id="totp_code">`
  # text field above `[update]` whenever the signed-in user had 2FA on.
  # Per the polish wave the inline field is gone; the form now mounts
  # the per-form `totp-modal` Stimulus controller, which intercepts
  # `[update]`, opens the layout-level TOTP verification modal, and
  # re-submits the form with `totp_code` injected as a hidden field
  # once the user enters all 6 digits.
  describe "Fix 4 (2026-05-11) — TOTP modal wiring" do
    it "drops the inline `totp_code` text input from the form (2FA on)" do
      get settings_user_path
      expect(response.body).not_to include('id="totp_code"')
      expect(response.body).not_to include('name="totp_code"')
      expect(response.body).not_to match(%r{<label[^>]*for="totp_code"})
    end

    it "wires `data-controller=\"totp-modal\"` on the form with required=yes when 2FA is on" do
      get settings_user_path
      expect(response.body).to match(
        /<form[^>]*data-controller="totp-modal"[^>]*data-totp-modal-required-value="yes"/m
      )
      # ERB escapes `->` to `-&gt;` in attribute output.
      expect(response.body).to include("submit-&gt;totp-modal#maybeIntercept")
    end
  end

  describe "unauthenticated access" do
    it "redirects GET /settings/user to /login", :unauthenticated do
      get settings_user_path
      expect(response).to redirect_to(login_path)
    end

    it "redirects PATCH /settings/user to /login", :unauthenticated do
      patch settings_user_path, params: { user: { username: "x_user" } }
      expect(response).to redirect_to(login_path)
    end
  end
end
