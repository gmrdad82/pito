require "rails_helper"

RSpec.describe "settings/security routing", type: :routing do
  it "GET /settings/security routes to Settings::SecurityController#show" do
    expect(get: "/settings/security").to route_to(
      controller: "settings/security",
      action: "show"
    )
  end
end
