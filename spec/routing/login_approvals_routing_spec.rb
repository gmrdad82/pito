require "rails_helper"

# Phase 25 — 01c. Routing specs for /login/approvals/:id and
# /login/blocks/:id.
RSpec.describe "Login approvals + blocks routes", type: :routing do
  describe "GET /login/approvals/:id" do
    it "routes to login/approvals#show" do
      expect(get: "/login/approvals/42").to route_to(
        controller: "login/approvals",
        action: "show",
        id: "42"
      )
    end
  end

  describe "POST /login/approvals/:id" do
    it "routes to login/approvals#create" do
      expect(post: "/login/approvals/42").to route_to(
        controller: "login/approvals",
        action: "create",
        id: "42"
      )
    end
  end

  describe "GET /login/blocks/:id" do
    it "routes to login/blocks#show" do
      expect(get: "/login/blocks/42").to route_to(
        controller: "login/blocks",
        action: "show",
        id: "42"
      )
    end
  end

  describe "POST /login/blocks/:id" do
    it "routes to login/blocks#create" do
      expect(post: "/login/blocks/42").to route_to(
        controller: "login/blocks",
        action: "create",
        id: "42"
      )
    end
  end

  it "rejects non-numeric ids on the approval show route" do
    expect(get: "/login/approvals/abc").not_to be_routable
  end

  it "rejects non-numeric ids on the block show route" do
    expect(get: "/login/blocks/abc").not_to be_routable
  end

  describe "named route helpers" do
    it "exposes login_approval_path with a positional id" do
      expect(login_approval_path(42)).to eq("/login/approvals/42")
    end

    it "exposes login_block_path with a positional id" do
      expect(login_block_path(42)).to eq("/login/blocks/42")
    end
  end
end
