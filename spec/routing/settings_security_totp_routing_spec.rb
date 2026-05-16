require "rails_helper"

# Phase 32 follow-up (2026-05-16). Routing pin for the slimmed
# 2FA / TOTP surface — two routes only (atomic enrollment).
RSpec.describe "TOTP routing", type: :routing do
  it "routes GET /settings/security/totp to totps#new" do
    expect(get: "/settings/security/totp").to route_to("settings/security/totps#new")
  end

  it "routes POST /settings/security/totp to totps#create" do
    expect(post: "/settings/security/totp").to route_to("settings/security/totps#create")
  end

  it "no longer routes GET /settings/security/totp/show (removed)" do
    expect(get: "/settings/security/totp/show").not_to be_routable
  end

  it "no longer routes PATCH /settings/security/totp/confirm (removed)" do
    expect(patch: "/settings/security/totp/confirm").not_to be_routable
  end

  it "no longer routes GET /settings/security/totp/disable (removed)" do
    expect(get: "/settings/security/totp/disable").not_to be_routable
  end

  it "no longer routes POST /settings/security/totp/disable (removed)" do
    expect(post: "/settings/security/totp/disable").not_to be_routable
  end

  it "no longer routes the totp_backup_codes show surface (removed)" do
    expect(get: "/settings/security/totp_backup_codes").not_to be_routable
  end

  it "no longer routes the totp_backup_codes new surface (removed)" do
    expect(get: "/settings/security/totp_backup_codes/new").not_to be_routable
  end

  it "no longer routes the totp_backup_codes create surface (removed)" do
    expect(post: "/settings/security/totp_backup_codes").not_to be_routable
  end

  # The login-time TOTP challenge stays — that surface is separate
  # from the settings enrollment surface this dispatch reworked.
  it "routes GET /login/totp to login/totp_challenges#show" do
    expect(get: "/login/totp").to route_to("login/totp_challenges#show")
  end

  it "routes POST /login/totp to login/totp_challenges#create" do
    expect(post: "/login/totp").to route_to("login/totp_challenges#create")
  end
end
