require "rails_helper"

RSpec.describe "Settings::Security::Blocks", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  describe "GET /settings/security/blocks" do
    let!(:active_row) do
      create(:blocked_location,
             source_surface: :web,
             fingerprint_hash: ("a" * 64),
             ip_prefix: "1.1.1.0/24")
    end
    let!(:tui_row) do
      create(:blocked_location,
             source_surface: :tui,
             fingerprint_hash: ("b" * 64),
             ip_prefix: "2.2.2.0/24")
    end
    let!(:unblocked_row) do
      create(:blocked_location, :unblocked,
             source_surface: :web,
             fingerprint_hash: ("c" * 64),
             ip_prefix: "3.3.3.0/24")
    end

    it "renders 200 and lists every block" do
      get settings_security_blocks_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("aaaaaaaaaaaa")
      expect(response.body).to include("bbbbbbbbbbbb")
      expect(response.body).to include("cccccccccccc")
    end

    it "shows the 'active' / 'unblocked' badges" do
      get settings_security_blocks_path
      expect(response.body).to include("active")
      expect(response.body).to include("unblocked")
    end

    it "filters by source_surface" do
      get settings_security_blocks_path, params: { source_surface: "tui" }
      expect(response.body).to include("bbbbbbbbbbbb")
      expect(response.body).not_to include("aaaaaaaaaaaa")
    end

    it "filters by active=yes (active rows only)" do
      get settings_security_blocks_path, params: { active: "yes" }
      expect(response.body).to include("aaaaaaaaaaaa")
      expect(response.body).not_to include("cccccccccccc")
    end

    it "filters by active=no (soft-unblocked rows only)" do
      get settings_security_blocks_path, params: { active: "no" }
      expect(response.body).to include("cccccccccccc")
      expect(response.body).not_to include("aaaaaaaaaaaa")
    end

    it "filters by fingerprint" do
      get settings_security_blocks_path, params: { fingerprint: "a" * 64 }
      expect(response.body).to include("aaaaaaaaaaaa")
      expect(response.body).not_to include("bbbbbbbbbbbb")
    end

    it "filters by ip_prefix" do
      get settings_security_blocks_path, params: { ip_prefix: "2.2.2.0/24" }
      expect(response.body).to include("bbbbbbbbbbbb")
      expect(response.body).not_to include("aaaaaaaaaaaa")
    end

    it "surfaces an alert on an invalid since timestamp but still renders 200" do
      get settings_security_blocks_path, params: { since: "garbage" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("invalid")
    end

    it "exposes the link to the purge surface" do
      get settings_security_blocks_path
      expect(response.body).to include(settings_security_blocks_purge_path)
    end

    it "shows the 'no blocks match' notice when filters narrow to nothing" do
      get settings_security_blocks_path, params: { fingerprint: "z" * 64 }
      expect(response.body).to include("no blocks match")
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get settings_security_blocks_path
      expect(response).to have_http_status(:found)
    end
  end

  describe "GET /settings/security/blocks/:id" do
    let(:row) { create(:blocked_location, attempt_count: 7) }

    it "renders the detail page" do
      get settings_security_block_path(row)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(row.fingerprint_hash)
      expect(response.body).to include(row.ip_prefix)
      expect(response.body).to include("7") # attempt_count
    end

    it "shows the soft-unblocked badge on an unblocked row" do
      unblocked = create(:blocked_location, :unblocked)
      get settings_security_block_path(unblocked)
      expect(response.body).to include("unblocked")
    end

    it "404s on an unknown id" do
      get settings_security_block_path(id: 999_999)
      expect(response).to have_http_status(:not_found)
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get settings_security_block_path(row)
      expect(response).to have_http_status(:found)
    end
  end
end
