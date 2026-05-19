require "rails_helper"
require "rake"

# Coverage push (2026-05-17). The legacy `tokens:*` rake namespace
# (renamed from `mcp:*` in Phase 3 Step B). Three thin tasks:
#
#   - `tokens:create[name,scope1+scope2+...]` — mints an `ApiToken`
#     for `User.first` and prints the plaintext + a curl example once.
#   - `tokens:list` — lists every token with name, scopes, status,
#     preview, last-used.
#   - `tokens:revoke[id]` — looks up by numeric id, calls `revoke!`.
#
# A newer `pito:tokens:*` namespace (covered by
# `spec/lib/tasks/pito_tokens_rake_spec.rb`) is operator-facing and
# more validated; this older namespace is preserved for backwards
# compatibility with older CLI muscle memory and is exercised here for
# parity.
RSpec.describe "tokens rake tasks" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/tokens",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:create_task) { Rake::Task["tokens:create"] }
  let(:list_task)   { Rake::Task["tokens:list"] }
  let(:revoke_task) { Rake::Task["tokens:revoke"] }

  before do
    create_task.reenable
    list_task.reenable
    revoke_task.reenable
    ApiToken.delete_all
  end

  describe "tokens:create" do
    let!(:owner) { create(:user) }

    it "creates a new ApiToken for User.first with the supplied scopes" do
      expect {
        capture_stdout { create_task.invoke("cli-token", "app") }
      }.to change { ApiToken.count }.by(1)

      token = ApiToken.order(:created_at).last
      expect(token.name).to eq("cli-token")
      expect(token.scopes).to match_array([ Scopes::APP ])
      expect(token.user_id).to eq(owner.id)
    end

    it "defaults name to `default` and scopes to `app` when args are omitted" do
      capture_stdout { create_task.invoke }
      token = ApiToken.order(:created_at).last
      expect(token.name).to eq("default")
      expect(token.scopes).to match_array([ Scopes::APP ])
    end

    it "splits a `+`-separated scope list into multiple scopes" do
      # The single-scope catalog means there's no "second" valid scope
      # to test multi-split with. Use a duplicate `app+app` to verify
      # the splitter behavior — the model accepts duplicate entries.
      capture_stdout { create_task.invoke("multi", "app+app") }
      token = ApiToken.find_by(name: "multi")
      expect(token.scopes).to match_array([ Scopes::APP, Scopes::APP ])
    end

    it "prints the token name, scopes, preview, and the one-time plaintext line" do
      output = capture_stdout { create_task.invoke("printable", "app") }
      token = ApiToken.find_by(name: "printable")

      expect(output).to include("token created: printable")
      expect(output).to include("scopes: app")
      expect(output).to include("preview: ...#{token.last_token_preview}")
      expect(output).to include("plaintext (copy now")
    end

    it "prints a curl example with the freshly minted plaintext" do
      # Phase 29 (MCP cut, 2026-05-19) — the example switched from the
      # retired `/mcp` JSON-RPC endpoint to the generic Rails JSON API
      # path the token now gates.
      output = capture_stdout { create_task.invoke("curlable", "app") }
      expect(output).to include("curl -H 'Authorization: Bearer ")
      expect(output).to include("http://localhost:3027/api/")
    end

    it "exits non-zero with a stderr message when no User is seeded" do
      User.delete_all
      expect {
        expect { create_task.invoke("orphan", "app") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/no User seeded — run bin\/rails db:seed first/).to_stderr
    end

    it "exits non-zero with a stderr message when scopes contain an invalid entry" do
      expect {
        expect { create_task.invoke("badscope", "bogus+app") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/invalid scopes: bogus/).to_stderr
    end

    it "discards empty entries when the scope string has stray separators" do
      capture_stdout { create_task.invoke("trim", "app+") }
      token = ApiToken.find_by(name: "trim")
      expect(token.scopes).to match_array([ Scopes::APP ])
    end
  end

  describe "tokens:list" do
    let!(:owner) { create(:user) }

    it "prints `no tokens.` when the table is empty" do
      expect { list_task.invoke }.to output(/no tokens\./).to_stdout
    end

    it "prints id, name, scopes, status, preview, last-used for each token" do
      token, _plain = ApiToken.generate!(user: owner, name: "alpha", scopes: [ Scopes::APP ])
      output = capture_stdout { list_task.invoke }

      expect(output).to include("#{token.id}. alpha")
      expect(output).to include("[app]")
      expect(output).to include("(active)")
      expect(output).to include("...#{token.last_token_preview}")
      expect(output).to include("last used: never")
    end

    it "labels revoked tokens as `revoked`" do
      token, _plain = ApiToken.generate!(user: owner, name: "old", scopes: [ Scopes::APP ])
      token.revoke!
      output = capture_stdout { list_task.invoke }
      expect(output).to include("(revoked)")
    end

    it "labels expired tokens as `expired`" do
      token, _plain = ApiToken.generate!(
        user: owner, name: "stale", scopes: [ Scopes::APP ],
        expires_at: 1.day.from_now
      )
      token.update_columns(expires_at: 1.day.ago)
      output = capture_stdout { list_task.invoke }
      expect(output).to include("(expired)")
    end

    it "prints last_used_at as the formatted timestamp when set" do
      token, _plain = ApiToken.generate!(user: owner, name: "used", scopes: [ Scopes::APP ])
      ts = Time.utc(2026, 4, 1, 12, 34, 0)
      token.update_columns(last_used_at: ts)

      output = capture_stdout { list_task.invoke }
      expect(output).to include("last used: #{ts.strftime('%Y-%m-%d %H:%M')}")
    end

    it "orders tokens newest-first" do
      a, _ = ApiToken.generate!(user: owner, name: "first", scopes: [ Scopes::APP ])
      b, _ = ApiToken.generate!(user: owner, name: "second", scopes: [ Scopes::APP ])
      a.update_columns(created_at: 2.days.ago)
      b.update_columns(created_at: 1.minute.ago)

      output = capture_stdout { list_task.invoke }
      first_idx  = output.index("first")
      second_idx = output.index("second")
      expect(second_idx).to be < first_idx
    end
  end

  describe "tokens:revoke" do
    let!(:owner) { create(:user) }
    let!(:token) do
      record, _plain = ApiToken.generate!(user: owner, name: "killme", scopes: [ Scopes::APP ])
      record
    end

    it "sets revoked_at on the row resolved by numeric id" do
      expect {
        capture_stdout { revoke_task.invoke(token.id.to_s) }
      }.to change { token.reload.revoked_at }.from(nil)
    end

    it "prints a confirmation line including the preview" do
      output = capture_stdout { revoke_task.invoke(token.id.to_s) }
      expect(output).to include("revoked: killme")
      expect(output).to include("...#{token.last_token_preview}")
    end

    it "exits non-zero with a stderr message when id is empty" do
      expect {
        expect { revoke_task.invoke("") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/id required: bin\/rails 'tokens:revoke\[<id>\]'/).to_stderr
    end

    it "raises ActiveRecord::RecordNotFound when the id is unknown" do
      missing = (ApiToken.maximum(:id).to_i + 9999).to_s
      expect {
        revoke_task.invoke(missing)
      }.to raise_error(ActiveRecord::RecordNotFound)
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
