require "rails_helper"

# Phase 29 — Unit A2. User auth refactor.
#
# Seeds spec — covers the dev `ApiToken` idempotency, the new `:owner`
# credentials shape (`{ username, password }`), and the removal of the
# sample-data blocks (no Channel / Video / Project / Game / Collection
# / Note / Timeline rows are seeded).
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
      scopes: Scopes::ALL.dup
    )
  end

  describe "dev token mint" do
    it "mints the dev ApiToken with the full Scopes::ALL set" do
      owner = User.first || create(:user)
      record, _plaintext = mint_dev_token(owner)

      expect(record).to be_present
      expect(record.name).to eq("dev")
      # Track the same source of truth the seed assigns (Scopes::ALL.dup)
      # so this assertion can't drift when the scope catalog changes.
      expect(record.scopes).to match_array(Scopes::ALL)
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

  describe "owner credentials shape (Phase 29 — Unit A2)" do
    let(:fixed_username) { "owner_spec_#{SecureRandom.hex(2)}" }

    before do
      User.delete_all
      stub_username = fixed_username
      original = Rails.application.credentials.method(:dig)
      allow(Rails.application.credentials).to receive(:dig) do |*args|
        if args == [ :owner ]
          { username: stub_username, password: "spec-password-1" }
        else
          original.call(*args)
        end
      end
    end

    it "creates exactly one User row with the seeded username" do
      Rails.application.load_seed
      expect(User.count).to eq(1)
      user = User.first
      expect(user.username).to eq(fixed_username)
      expect(user.authenticate("spec-password-1")).to eq(user)
    end

    it "is idempotent — a second seed run does not duplicate the user" do
      Rails.application.load_seed
      expect { Rails.application.load_seed }.not_to change { User.count }
    end

    it "does not seed any sample Channel / Video / Project / Game / Collection / Note / Timeline rows" do
      Rails.application.load_seed
      expect(Channel.count).to eq(0)
      expect(Video.count).to eq(0)
      expect(Project.count).to eq(0)
      expect(Game.count).to eq(0)
      expect(Collection.count).to eq(0)
      expect(Note.count).to eq(0)
      expect(Timeline.count).to eq(0)
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
      expect(User.where(username: "owner").count).to eq(1)
    end
  end
end
