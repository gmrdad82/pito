require "rails_helper"
require "rake"

# Phase 32 follow-up (2026-05-16). Operator-only management of
# `ApiToken` rows. Specs mirror the `pito:oauth_apps:*` style.
RSpec.describe "pito:tokens rake tasks" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/pito_tokens",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:list_task)   { Rake::Task["pito:tokens:list"] }
  let(:mint_task)   { Rake::Task["pito:tokens:mint"] }
  let(:revoke_task) { Rake::Task["pito:tokens:revoke"] }

  let(:owner) { User.first || create(:user) }

  before do
    list_task.reenable
    mint_task.reenable
    revoke_task.reenable
    owner # touch lazy let so a User row exists
    ApiToken.delete_all
  end

  describe "pito:tokens:list" do
    it "prints a no-op message when no tokens exist" do
      expect { list_task.invoke }.to output(/no API tokens minted\./).to_stdout
    end

    it "prints id + name + scopes + status + preview + timestamps (no plaintext)" do
      token, plaintext = ApiToken.generate!(
        user: owner, name: "alpha-token",
        scopes: [ Scopes::APP ]
      )

      output = capture_stdout { list_task.invoke }

      expect(output).to include("alpha-token")
      expect(output).to include("app")
      expect(output).to include("...#{token.last_token_preview}")
      expect(output).to include("active")
      # Plaintext is never re-derivable from the digest — but assert
      # defense-in-depth that the captured plaintext never appears in
      # the listing output.
      expect(output).not_to include(plaintext)
    end

    it "labels revoked + expired tokens distinctly" do
      revoked, = ApiToken.generate!(user: owner, name: "old-revoked", scopes: [ Scopes::APP ])
      revoked.revoke!
      ApiToken.generate!(user: owner, name: "still-good", scopes: [ Scopes::APP ])

      output = capture_stdout { list_task.invoke }

      expect(output).to include("old-revoked")
      expect(output).to include("still-good")
      expect(output).to include("revoked")
      expect(output).to include("active")
    end
  end

  describe "pito:tokens:mint" do
    it "creates a new ApiToken with the chosen scopes for the seeded owner user" do
      expect {
        mint_task.invoke("cli", "app")
      }.to change { ApiToken.count }.by(1)

      token = ApiToken.order(:created_at).last
      expect(token.name).to eq("cli")
      expect(token.scopes).to match_array([ Scopes::APP ])
      expect(token.user_id).to eq(owner.id)
    end

    it "prints the save-it-now header + the plaintext exactly once on stdout" do
      output = capture_stdout do
        mint_task.invoke("cli2", "app+dev")
      end
      expect(output).to include("save the plaintext now")
      token = ApiToken.find_by(name: "cli2")
      expect(output).to include("...#{token.last_token_preview}")
      # The plaintext line is on its own — assert the preview is
      # embedded in the output by matching the structural label.
      expect(output).to match(/plaintext: [A-Za-z0-9_\-]{40,}/)
    end

    it "exits non-zero with a stderr message when name is empty" do
      expect {
        expect { mint_task.invoke("", "app") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/name required/).to_stderr
    end

    it "exits non-zero with a stderr message when scopes are empty" do
      expect {
        expect { mint_task.invoke("noscopes", "") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/scopes required/).to_stderr
    end

    it "exits non-zero with a stderr message when scopes contain an invalid entry" do
      expect {
        expect { mint_task.invoke("badscope", "bogus+app") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/invalid scopes: bogus/).to_stderr
    end

    it "exits non-zero with a stderr message when no User is seeded" do
      User.delete_all
      expect {
        expect { mint_task.invoke("orphan", "app") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/no User seeded/).to_stderr
    end
  end

  describe "pito:tokens:revoke" do
    let!(:token) do
      record, = ApiToken.generate!(user: owner, name: "to-revoke", scopes: [ Scopes::APP ])
      record
    end

    it "soft-deletes by name (sets revoked_at; row stays)" do
      expect {
        revoke_task.invoke("to-revoke")
      }.not_to change { ApiToken.count }
      expect(token.reload.revoked_at).to be_present
    end

    it "soft-deletes by numeric id" do
      revoke_task.invoke(token.id.to_s)
      expect(token.reload.revoked_at).to be_present
    end

    it "prints a confirmation line including the preview" do
      output = capture_stdout { revoke_task.invoke("to-revoke") }
      expect(output).to include("revoked API token 'to-revoke'")
      expect(output).to include("preview=...#{token.last_token_preview}")
    end

    it "is idempotent on an already-revoked token (no-op, no error)" do
      token.revoke!
      original_revoked_at = token.revoked_at
      expect { revoke_task.invoke("to-revoke") }
        .to output(/already revoked/).to_stdout
      expect(token.reload.revoked_at.to_i).to eq(original_revoked_at.to_i)
    end

    it "exits non-zero with a stderr message when id_or_name is empty" do
      expect {
        expect { revoke_task.invoke("") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/id_or_name required/).to_stderr
    end

    it "exits non-zero with a stderr message when the lookup misses" do
      expect {
        expect { revoke_task.invoke("no-such-token") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/token not found/).to_stderr
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
