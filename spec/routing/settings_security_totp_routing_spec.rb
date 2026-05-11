require "rails_helper"

# Phase 25 — 01e. Routing pin for the TOTP 2FA management surface.
RSpec.describe "TOTP routing", type: :routing do
  it "routes GET /settings/security/totp to totps#new" do
    expect(get: "/settings/security/totp").to route_to("settings/security/totps#new")
  end

  it "routes POST /settings/security/totp to totps#create" do
    expect(post: "/settings/security/totp").to route_to("settings/security/totps#create")
  end

  it "routes GET /settings/security/totp/show to totps#show" do
    expect(get: "/settings/security/totp/show").to route_to("settings/security/totps#show")
  end

  it "routes PATCH /settings/security/totp/confirm to totps#update" do
    expect(patch: "/settings/security/totp/confirm").to route_to("settings/security/totps#update")
  end

  it "routes GET /settings/security/totp/disable to totps#destroy_screen" do
    expect(get: "/settings/security/totp/disable").to route_to("settings/security/totps#destroy_screen")
  end

  it "routes POST /settings/security/totp/disable to totps#destroy_confirmed" do
    expect(post: "/settings/security/totp/disable").to route_to("settings/security/totps#destroy_confirmed")
  end

  it "routes GET /settings/security/totp_backup_codes to totp_backup_codes#show" do
    expect(get: "/settings/security/totp_backup_codes").to route_to("settings/security/totp_backup_codes#show")
  end

  it "routes GET /settings/security/totp_backup_codes/new to totp_backup_codes#new" do
    expect(get: "/settings/security/totp_backup_codes/new").to route_to("settings/security/totp_backup_codes#new")
  end

  it "routes POST /settings/security/totp_backup_codes to totp_backup_codes#create" do
    expect(post: "/settings/security/totp_backup_codes").to route_to("settings/security/totp_backup_codes#create")
  end

  it "routes GET /login/totp to login/totp_challenges#show" do
    expect(get: "/login/totp").to route_to("login/totp_challenges#show")
  end

  it "routes POST /login/totp to login/totp_challenges#create" do
    expect(post: "/login/totp").to route_to("login/totp_challenges#create")
  end
end
