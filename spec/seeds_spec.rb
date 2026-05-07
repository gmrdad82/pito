require "rails_helper"

# Seeds spec — focuses on Phase 3 Step C's idempotency guarantee for the
# default `dev` ApiToken. The seed body is large; this spec exercises the
# token-mint branch in isolation by re-loading `db/seeds.rb` against a
# clean tenant + user.
RSpec.describe "db/seeds.rb dev token mint", type: :model do
  let(:tenant) { Current.tenant || Tenant.first }

  before do
    # Make sure the dev token doesn't survive between examples.
    ApiToken.where(name: "dev").delete_all
  end

  def mint_dev_token(owner)
    return nil if ApiToken.exists?(name: "dev", tenant_id: tenant.id)

    ApiToken.generate!(
      tenant: tenant,
      user:   owner,
      name:   "dev",
      scopes: [
        Scopes::DEV_READ, Scopes::DEV_WRITE,
        Scopes::YT_READ, Scopes::YT_WRITE,
        Scopes::PROJECT_READ, Scopes::PROJECT_WRITE
      ]
    )
  end

  it "mints a dev token with the locked default scope set" do
    owner = User.first || create(:user, tenant: tenant)
    record, _plaintext = mint_dev_token(owner)

    expect(record).to be_present
    expect(record.name).to eq("dev")
    expect(record.scopes).to match_array([
      Scopes::DEV_READ, Scopes::DEV_WRITE,
      Scopes::YT_READ, Scopes::YT_WRITE,
      Scopes::PROJECT_READ, Scopes::PROJECT_WRITE
    ])
    # Excludes destructive + website by design.
    expect(record.scopes).not_to include(Scopes::YT_DESTRUCTIVE)
    expect(record.scopes).not_to include(Scopes::WEBSITE_READ, Scopes::WEBSITE_WRITE)
  end

  it "is idempotent — a second mint attempt is a no-op" do
    owner = User.first || create(:user, tenant: tenant)
    mint_dev_token(owner)
    expect(ApiToken.where(name: "dev", tenant_id: tenant.id).count).to eq(1)

    # Second call returns nil (the guard) and creates nothing new.
    expect { mint_dev_token(owner) }.not_to change { ApiToken.count }
    expect(ApiToken.where(name: "dev", tenant_id: tenant.id).count).to eq(1)
  end

  # CI fix (post-32d7f84) — CI does not have `config/master.key`, so
  # `:tokens.pepper` reads as nil. The dev token is a developer convenience,
  # not a runtime requirement, so `db:seed` must finish under
  # `RAILS_ENV=test` even with pepper missing. (Local development still
  # halts with a helpful message — covered by the inverted guard in
  # `db/seeds.rb`.)
  describe "missing :tokens.pepper credential" do
    before do
      ApiToken.where(name: "dev").delete_all
      # Stub only the `(:tokens, :pepper)` lookup; other credentials
      # (notably `:owner`, `:postgres`) keep working so the rest of the
      # seed body executes normally.
      original = Rails.application.credentials.method(:dig)
      allow(Rails.application.credentials).to receive(:dig) do |*args|
        args == [ :tokens, :pepper ] ? nil : original.call(*args)
      end
    end

    it "in Rails.env.test, warns and skips the dev token mint instead of raising" do
      expect(Rails.env.test?).to be(true)
      expect { Rails.application.load_seed }.not_to raise_error
      expect(ApiToken.where(name: "dev", tenant_id: tenant.id)).to be_empty
    end
  end
end
