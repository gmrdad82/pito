require "rails_helper"

RSpec.describe "settings/security routing", type: :routing do
  it "GET /settings/security routes to Settings::SecurityController#show" do
    expect(get: "/settings/security").to route_to(
      controller: "settings/security",
      action: "show"
    )
  end

  it "GET /settings/security/attempts routes to Settings::Security::AttemptsController#index" do
    expect(get: "/settings/security/attempts").to route_to(
      controller: "settings/security/attempts",
      action: "index"
    )
  end

  it "GET /settings/security/attempts/:id routes to Settings::Security::AttemptsController#show" do
    expect(get: "/settings/security/attempts/42").to route_to(
      controller: "settings/security/attempts",
      action: "show",
      id: "42"
    )
  end
end
