require "rails_helper"

# Phase 12 — user account self-service. The authenticated user can
# change their own email or password. `current_password` is required
# for either mutation. No delete-account, no create-user, no
# password-recovery flow on this surface.
RSpec.describe "Settings::User", type: :request do
  let(:password) { "supersecret123" }
  let(:user) do
    User.first || create(:user, password: password, password_confirmation: password)
  end

  before do |example|
    next if example.metadata[:unauthenticated]

    user.update!(password: password, password_confirmation: password)
    sign_in_as(user)
  end

  describe "GET /settings/user" do
    it "renders the form pre-filled with the current email" do
      get settings_user_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("user")
      expect(response.body).to include(user.email)
      expect(response.body).to include("current password")
      expect(response.body).to include("new password")
    end
  end

  describe "PATCH /settings/user" do
    it "updates the email when current_password is correct and email changed" do
      new_email = "new-#{SecureRandom.hex(4)}@example.test"

      patch settings_user_path, params: {
        user: {
          email: new_email,
          current_password: password,
          password: "",
          password_confirmation: ""
        }
      }

      expect(response).to redirect_to(settings_path)
      expect(flash[:notice]).to be_present
      expect(user.reload.email).to eq(new_email)
    end

    it "updates the password when current_password and confirmation match" do
      new_password = "freshpassword456"

      patch settings_user_path, params: {
        user: {
          email: user.email,
          current_password: password,
          password: new_password,
          password_confirmation: new_password
        }
      }

      expect(response).to redirect_to(settings_path)
      expect(flash[:notice]).to be_present
      expect(user.reload.authenticate(new_password)).to be_truthy
      expect(user.authenticate(password)).to be(false)
    end

    it "rejects when password and confirmation do not match" do
      original_email = user.email
      original_digest = user.password_digest

      patch settings_user_path, params: {
        user: {
          email: user.email,
          current_password: password,
          password: "freshpassword456",
          password_confirmation: "different789"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("does not match")
      expect(user.reload.email).to eq(original_email)
      expect(user.password_digest).to eq(original_digest)
    end

    it "rejects when current_password is wrong and does not mutate the user" do
      original_email = user.email
      original_digest = user.password_digest

      patch settings_user_path, params: {
        user: {
          email: "should-not-stick@example.test",
          current_password: "wrong-password",
          password: "freshpassword456",
          password_confirmation: "freshpassword456"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("incorrect")
      expect(user.reload.email).to eq(original_email)
      expect(user.password_digest).to eq(original_digest)
    end

    it "updates only the email when new password fields are blank" do
      new_email = "only-email-#{SecureRandom.hex(4)}@example.test"
      original_digest = user.password_digest

      patch settings_user_path, params: {
        user: {
          email: new_email,
          current_password: password,
          password: "",
          password_confirmation: ""
        }
      }

      expect(response).to redirect_to(settings_path)
      expect(user.reload.email).to eq(new_email)
      expect(user.password_digest).to eq(original_digest)
    end

    it "rejects when current_password is blank" do
      original_email = user.email
      original_digest = user.password_digest

      patch settings_user_path, params: {
        user: {
          email: "blank-pw@example.test",
          current_password: "",
          password: "",
          password_confirmation: ""
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.email).to eq(original_email)
      expect(user.password_digest).to eq(original_digest)
    end

    it "ignores smuggled extra params (admin / role / etc.)" do
      new_email = "smuggle-#{SecureRandom.hex(4)}@example.test"

      patch settings_user_path, params: {
        user: {
          email: new_email,
          current_password: password,
          password: "",
          password_confirmation: "",
          admin: true,
          role: "owner",
          password_digest: "stolen"
        }
      }

      expect(response).to redirect_to(settings_path)
      user.reload
      expect(user.email).to eq(new_email)
      # The User model has no admin/role columns, so the extra params
      # are inert by schema. The password_digest must not have been
      # rewritten by the smuggled key — verify by re-authenticating
      # against the original password.
      expect(user.authenticate(password)).to be_truthy
    end

    it "re-renders the form when email validation fails" do
      original_email = user.email

      patch settings_user_path, params: {
        user: {
          email: "not-an-email",
          current_password: password,
          password: "",
          password_confirmation: ""
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.email).to eq(original_email)
    end
  end

  describe "unauthenticated access" do
    it "redirects GET /settings/user to /login", :unauthenticated do
      get settings_user_path
      expect(response).to redirect_to(login_path)
    end

    it "redirects PATCH /settings/user to /login", :unauthenticated do
      patch settings_user_path, params: { user: { email: "x@example.test" } }
      expect(response).to redirect_to(login_path)
    end
  end
end
