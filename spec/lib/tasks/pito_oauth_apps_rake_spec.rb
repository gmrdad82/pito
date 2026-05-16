require "rails_helper"
require "rake"

# Phase 32 follow-up (2026-05-16). Operator-only management of
# Doorkeeper OAuth applications. Specs mirror the
# `pito:user:reset_totp` style — load the task file in isolation,
# reinvoke, assert on DB side effects + the operator-facing lines on
# stdout / stderr.
RSpec.describe "pito:oauth_apps rake tasks" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/pito_oauth_apps",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:list_task)   { Rake::Task["pito:oauth_apps:list"] }
  let(:mint_task)   { Rake::Task["pito:oauth_apps:mint"] }
  let(:show_task)   { Rake::Task["pito:oauth_apps:show"] }
  let(:revoke_task) { Rake::Task["pito:oauth_apps:revoke"] }

  before do
    list_task.reenable
    mint_task.reenable
    show_task.reenable
    revoke_task.reenable
    OauthApplication.delete_all
  end

  describe "pito:oauth_apps:list" do
    it "prints a no-op message when no applications are registered" do
      expect { list_task.invoke }.to output(/no OAuth applications registered\./).to_stdout
    end

    it "prints id, name, client_id, redirect_uri, scopes for each application (NOT secret)" do
      app = OauthApplication.create!(
        name: "list-target",
        redirect_uri: "http://127.0.0.1:9000/cb",
        scopes: "app",
        confidential: true
      )

      output = capture_stdout { list_task.invoke }

      expect(output).to include("list-target")
      expect(output).to include(app.uid)
      expect(output).to include("http://127.0.0.1:9000/cb")
      expect(output).to include("scopes:")
      # client_secret must never appear in the list output.
      secret = app.plaintext_secret || app.secret
      expect(output).not_to include(secret) if secret.present?
    end
  end

  describe "pito:oauth_apps:mint" do
    it "creates a new application and prints client_id + client_secret once" do
      expect {
        mint_task.invoke("desktop", "http://127.0.0.1:9999/callback", "app")
      }.to change(OauthApplication, :count).by(1)

      app = OauthApplication.find_by(name: "desktop")
      expect(app).not_to be_nil
      expect(app.redirect_uri).to eq("http://127.0.0.1:9999/callback")
      expect(app.scopes).to include("app")
      expect(app.confidential?).to be(true)
    end

    it "prints the save-it-now header + client_secret on stdout" do
      output = capture_stdout do
        mint_task.invoke("desktop2", "http://127.0.0.1:9999/callback", "app")
      end
      expect(output).to include("save the client_secret now")
      app = OauthApplication.find_by(name: "desktop2")
      secret = app.plaintext_secret || app.secret
      expect(output).to include(secret)
      expect(output).to include(app.uid)
    end

    it "defaults to Scopes::ALL when the third argument is omitted" do
      mint_task.invoke("default-scopes", "http://127.0.0.1:9999/callback")
      app = OauthApplication.find_by(name: "default-scopes")
      expect(app.scopes.to_s.split(" ")).to match_array(Scopes::ALL)
    end

    it "exits non-zero with a stderr message when name is empty" do
      expect {
        expect {
          mint_task.invoke("", "http://127.0.0.1:9999/callback", "app")
        }.to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/name required/).to_stderr
    end

    it "exits non-zero with a stderr message when redirect_uri is empty" do
      expect {
        expect {
          mint_task.invoke("desktop", "", "app")
        }.to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/redirect_uri required/).to_stderr
    end

    it "exits non-zero with a stderr message when scopes contain an invalid entry" do
      expect {
        expect {
          mint_task.invoke("desktop", "http://127.0.0.1:9999/callback", "bogus+app")
        }.to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/invalid scopes: bogus/).to_stderr
    end
  end

  describe "pito:oauth_apps:show" do
    let!(:app) do
      OauthApplication.create!(
        name: "show-target",
        redirect_uri: "http://127.0.0.1:9001/cb",
        scopes: "app",
        confidential: true
      )
    end

    it "resolves by numeric id and prints metadata (no secret)" do
      output = capture_stdout { show_task.invoke(app.id.to_s) }
      expect(output).to include("show-target")
      expect(output).to include(app.uid)
      expect(output).to include("http://127.0.0.1:9001/cb")
      secret = app.plaintext_secret || app.secret
      expect(output).not_to include(secret) if secret.present?
    end

    it "resolves by client_id (uid)" do
      output = capture_stdout { show_task.invoke(app.uid) }
      expect(output).to include("show-target")
    end

    it "exits non-zero with a stderr message when id_or_client_id is empty" do
      expect {
        expect { show_task.invoke("") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/id_or_client_id required/).to_stderr
    end

    it "exits non-zero with a stderr message when the lookup misses" do
      expect {
        expect { show_task.invoke("nonexistent-client-id") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/application not found/).to_stderr
    end
  end

  describe "pito:oauth_apps:revoke" do
    let!(:app) do
      OauthApplication.create!(
        name: "revoke-target",
        redirect_uri: "http://127.0.0.1:9002/cb",
        scopes: "app",
        confidential: true
      )
    end

    it "refuses to delete without force=true (stderr + non-zero exit)" do
      expect {
        expect { revoke_task.invoke(app.id.to_s) }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/refusing to revoke without force=true/).to_stderr

      expect(OauthApplication.exists?(app.id)).to be(true)
    end

    it "deletes the application when force=true is supplied" do
      revoke_task.invoke(app.id.to_s, "force")
      expect(OauthApplication.exists?(app.id)).to be(false)
    end

    it "revokes outstanding access tokens + grants tied to the application" do
      access_token = OauthAccessToken.create!(
        application: app,
        resource_owner_id: User.first&.id || create(:user).id,
        scopes: "app",
        expires_in: 7200
      )
      access_grant = OauthAccessGrant.create!(
        application: app,
        resource_owner_id: User.first&.id || create(:user).id,
        token: SecureRandom.hex(32),
        redirect_uri: app.redirect_uri,
        scopes: "app",
        expires_in: 600
      )

      revoke_task.invoke(app.id.to_s, "force")

      expect(OauthApplication.exists?(app.id)).to be(false)
      # Tokens + grants either deleted (Doorkeeper cascade) or
      # revoked (`update_all` in the task) — both leave the row
      # unusable. We assert the unusable state symmetrically with
      # `Settings::OauthApplicationsController#destroy`'s prior
      # contract.
      reloaded_token = OauthAccessToken.where(id: access_token.id).first
      reloaded_grant = OauthAccessGrant.where(id: access_grant.id).first
      expect(reloaded_token.nil? || reloaded_token.revoked_at.present?).to be(true)
      expect(reloaded_grant.nil? || reloaded_grant.revoked_at.present?).to be(true)
    end

    it "exits non-zero with a stderr message when id_or_client_id is empty" do
      expect {
        expect { revoke_task.invoke("") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/id_or_client_id required/).to_stderr
    end

    it "exits non-zero with a stderr message when the lookup misses" do
      expect {
        expect { revoke_task.invoke("missing-client-id", "force") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/application not found/).to_stderr
    end
  end

  private

  def capture_stdout
    original = $stdout
    captured = StringIO.new
    $stdout = captured
    yield
    captured.string
  ensure
    $stdout = original
  end
end
