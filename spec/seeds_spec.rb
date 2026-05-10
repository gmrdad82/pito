require "rails_helper"

# Phase 8 — Tenant Drop + Email-Only Login (ADR 0003).
#
# Seeds spec — focuses on idempotency for the default `dev` ApiToken
# and the new `:owner` credentials shape (`{ email, password }`).
RSpec.describe "db/seeds.rb", type: :model do
  before do
    # Make sure the dev token doesn't survive between examples.
    ApiToken.where(name: "dev").delete_all
  end

  def mint_dev_token(owner)
    return nil if ApiToken.exists?(name: "dev")

    ApiToken.generate!(
      user:   owner,
      name:   "dev",
      scopes: [
        Scopes::DEV_READ, Scopes::DEV_WRITE,
        Scopes::YT_READ, Scopes::YT_WRITE,
        Scopes::PROJECT_READ, Scopes::PROJECT_WRITE
      ]
    )
  end

  describe "dev token mint" do
    it "mints a dev token with the locked default scope set" do
      owner = User.first || create(:user)
      record, _plaintext = mint_dev_token(owner)

      expect(record).to be_present
      expect(record.name).to eq("dev")
      expect(record.scopes).to match_array([
        Scopes::DEV_READ, Scopes::DEV_WRITE,
        Scopes::YT_READ, Scopes::YT_WRITE,
        Scopes::PROJECT_READ, Scopes::PROJECT_WRITE
      ])
      expect(record.scopes).not_to include(Scopes::YT_DESTRUCTIVE)
      expect(record.scopes).not_to include(Scopes::WEBSITE_READ, Scopes::WEBSITE_WRITE)
    end

    it "is idempotent — a second mint attempt is a no-op" do
      owner = User.first || create(:user)
      mint_dev_token(owner)
      expect(ApiToken.where(name: "dev").count).to eq(1)

      expect { mint_dev_token(owner) }.not_to change { ApiToken.count }
      expect(ApiToken.where(name: "dev").count).to eq(1)
    end
  end

  describe "missing :tokens.pepper credential" do
    before do
      ApiToken.where(name: "dev").delete_all
      original = Rails.application.credentials.method(:dig)
      allow(Rails.application.credentials).to receive(:dig) do |*args|
        args == [ :tokens, :pepper ] ? nil : original.call(*args)
      end
    end

    it "in Rails.env.test, warns and skips the dev token mint instead of raising" do
      expect(Rails.env.test?).to be(true)
      expect { Rails.application.load_seed }.not_to raise_error
      expect(ApiToken.where(name: "dev")).to be_empty
    end
  end

  describe "owner credentials shape (Phase 8)" do
    let(:fixed_email) { "owner-spec-#{SecureRandom.hex(2)}@example.test" }

    before do
      User.delete_all
      stub_email = fixed_email
      original = Rails.application.credentials.method(:dig)
      allow(Rails.application.credentials).to receive(:dig) do |*args|
        if args == [ :owner ]
          { email: stub_email, password: "spec-password-1" }
        else
          original.call(*args)
        end
      end
    end

    it "creates exactly one User row with the seeded email" do
      Rails.application.load_seed
      expect(User.count).to eq(1)
      user = User.first
      expect(user.email).to eq(fixed_email)
      expect(user.authenticate("spec-password-1")).to eq(user)
    end

    it "is idempotent — a second seed run does not duplicate the user" do
      Rails.application.load_seed
      expect { Rails.application.load_seed }.not_to change { User.count }
    end
  end

  describe "missing :owner credentials block" do
    before do
      User.delete_all
      original = Rails.application.credentials.method(:dig)
      allow(Rails.application.credentials).to receive(:dig) do |*args|
        args == [ :owner ] ? nil : original.call(*args)
      end
    end

    it "falls back to placeholder values without raising" do
      expect { Rails.application.load_seed }.not_to raise_error
      expect(User.where(email: "owner@example.test").count).to eq(1)
    end
  end
end
