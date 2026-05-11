require "rails_helper"

# Phase 25 — 01b (LD-17). Routing spec for the new-location challenge
# surface. Pins the friendly URLs locked in the umbrella spec.
RSpec.describe "Login challenge routes", type: :routing do
  it "routes GET /login/challenge to login/challenges#show" do
    expect(get: "/login/challenge").to route_to("login/challenges#show")
  end

  it "routes POST /login/challenge to login/challenges#create" do
    expect(post: "/login/challenge").to route_to("login/challenges#create")
  end

  it "routes GET /login/pending to login/pendings#show" do
    expect(get: "/login/pending").to route_to("login/pendings#show")
  end

  it "routes DELETE /login/pending to login/pendings#destroy" do
    expect(delete: "/login/pending").to route_to("login/pendings#destroy")
  end

  it "exposes the named route helper :login_challenge" do
    expect(login_challenge_path).to eq("/login/challenge")
  end

  it "exposes the named route helper :login_pending" do
    expect(login_pending_path).to eq("/login/pending")
  end

  it "exposes the named route helper :login_totp (placeholder)" do
    expect(login_totp_path).to eq("/login/totp")
  end

  private

  # Make the named route helpers available inside an example. Rails
  # routing specs don't auto-include url_helpers; we delegate to
  # `Rails.application.routes.url_helpers` for the three helpers under
  # test.
  def login_challenge_path
    Rails.application.routes.url_helpers.login_challenge_path
  end

  def login_pending_path
    Rails.application.routes.url_helpers.login_pending_path
  end

  def login_totp_path
    Rails.application.routes.url_helpers.login_totp_path
  end
end
