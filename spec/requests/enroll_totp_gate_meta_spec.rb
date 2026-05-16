require "rails_helper"

# 2026-05-16 — the mandatory-2FA enrollment gate signal that the
# `keyboard`, `leader-menu`, and `theme` Stimulus controllers consume
# lives in `<meta name="pito-enroll-totp-gate" content="yes|no">` in
# `<head>`. Body data-attributes and inline body `<script>`s both
# drifted stale on Turbo Drive navigation + the post-login redirect;
# Turbo's `mergeProvisionalElements` reliably re-merges head children
# so the meta surface is the stable one.
#
# This spec locks the contract:
#   * The meta tag renders on every layout-mounted page
#     (defensive — a missing tag would silently flip the gate off).
#   * `content="yes"` exactly when the authenticated user has not
#     configured TOTP; `content="no"` otherwise (including the
#     unauthenticated /login screen).
#   * The legacy body-mounted signals are gone.
RSpec.describe "mandatory-2FA enrollment gate — head <meta> signal", type: :request do
  let(:password) { "supersecret123" }
  let(:seed)     { "JBSWY3DPEHPK3PXP" }

  describe "authenticated user WITH TOTP configured (default fixture)" do
    # The shared `before(:each, type: :request)` block in
    # `spec/support/auth.rb` mints a TOTP-configured user and signs them
    # in, so requests below run against the gate-inactive branch.
    it "renders <meta name=\"pito-enroll-totp-gate\" content=\"no\"> in <head> on /" do
      get "/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        '<meta name="pito-enroll-totp-gate" content="no">'
      )
    end

    it "renders the same meta tag on /channels (post-Turbo-nav target)" do
      get "/channels"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        '<meta name="pito-enroll-totp-gate" content="no">'
      )
    end

    it "renders the same meta tag on /videos" do
      get "/videos"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        '<meta name="pito-enroll-totp-gate" content="no">'
      )
    end

    it "renders the same meta tag on /settings" do
      get "/settings"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        '<meta name="pito-enroll-totp-gate" content="no">'
      )
    end

    it "drops the retired inline body <script> that set window.__pitoEnrollTotpGate" do
      get "/"
      expect(response.body).not_to include("window.__pitoEnrollTotpGate")
      expect(response.body).not_to include("__pitoEnrollTotpGate")
    end

    it "drops the retired body data-enroll-totp-gate attribute" do
      get "/"
      expect(response.body).not_to include("data-enroll-totp-gate")
    end
  end

  describe "authenticated user WITHOUT TOTP configured (gate active)",
           :unauthenticated do
    let!(:unconfigured_user) do
      create(:user, password: password, password_confirmation: password)
    end

    before { sign_in_as(unconfigured_user) }

    # The mandatory-2FA gate redirects every non-allowlisted route to
    # `/settings?enroll_totp=1`. `/settings` itself is allowlisted so
    # the meta-tag assertion can run there without a redirect.
    it "renders <meta name=\"pito-enroll-totp-gate\" content=\"yes\"> on the enrollment landing /settings" do
      get settings_path(enroll_totp: 1)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        '<meta name="pito-enroll-totp-gate" content="yes">'
      )
    end

    it "renders the same gate=yes meta on the TOTP enrollment view itself" do
      get settings_security_totp_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        '<meta name="pito-enroll-totp-gate" content="yes">'
      )
    end
  end

  describe "unauthenticated /login screen", :unauthenticated do
    it "renders <meta ... content=\"no\"> (no user → gate is never active)" do
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        '<meta name="pito-enroll-totp-gate" content="no">'
      )
    end
  end

  describe "the meta tag sits in <head>, not <body>" do
    it "places the gate marker above </head>" do
      get "/"
      head_close_index = response.body.index("</head>")
      meta_index = response.body.index('name="pito-enroll-totp-gate"')

      expect(head_close_index).not_to be_nil
      expect(meta_index).not_to be_nil
      expect(meta_index).to be < head_close_index
    end
  end
end
