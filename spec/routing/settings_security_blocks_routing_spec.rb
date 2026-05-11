require "rails_helper"

RSpec.describe "Settings::Security::Blocks routing", type: :routing do
  describe "blocks" do
    it "routes GET /settings/security/blocks to blocks#index" do
      expect(get: "/settings/security/blocks").to route_to(
        controller: "settings/security/blocks",
        action: "index"
      )
    end

    it "routes GET /settings/security/blocks/:id to blocks#show" do
      expect(get: "/settings/security/blocks/42").to route_to(
        controller: "settings/security/blocks",
        action: "show",
        id: "42"
      )
    end
  end

  describe "blocks purge" do
    it "routes GET /settings/security/blocks/purge to blocks/purges#show" do
      expect(get: "/settings/security/blocks/purge").to route_to(
        controller: "settings/security/blocks/purges",
        action: "show"
      )
    end

    it "routes POST /settings/security/blocks/purge to blocks/purges#create" do
      expect(post: "/settings/security/blocks/purge").to route_to(
        controller: "settings/security/blocks/purges",
        action: "create"
      )
    end
  end

  describe "attempts purge" do
    it "routes GET /settings/security/attempts/purge to attempts/purges#show" do
      expect(get: "/settings/security/attempts/purge").to route_to(
        controller: "settings/security/attempts/purges",
        action: "show"
      )
    end

    it "routes POST /settings/security/attempts/purge to attempts/purges#create" do
      expect(post: "/settings/security/attempts/purge").to route_to(
        controller: "settings/security/attempts/purges",
        action: "create"
      )
    end
  end
end
