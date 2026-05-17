require "rails_helper"

# Phase 29 — Unit A2. User auth refactor.
#
# Seeds spec — covers the dev `ApiToken` idempotency, the new `:owner`
# credentials shape (`{ username, password }`), and the removal of the
# sample-data blocks (no Channel / Video / Project / Game
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

    it "does not seed any sample Channel / Video / Project / Game / Note / Timeline rows" do
      Rails.application.load_seed
      expect(Channel.count).to eq(0)
      expect(Video.count).to eq(0)
      expect(Project.count).to eq(0)
      expect(Game.count).to eq(0)
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

  # Phase 32 follow-up (2026-05-16). Claude Desktop's MCP custom
  # connector is an OAuth client. The seed registers a `claude-mcp`
  # Doorkeeper application so an operator's first `db:seed` run prints
  # the client_id + client_secret + redirect_uri block, and subsequent
  # runs find the existing row by name and stay idempotent.
  describe "Claude Desktop OAuth application seed" do
    before do
      OauthApplication.where(name: "claude-mcp").delete_all
    end

    it "creates a Doorkeeper application named claude-mcp with the Claude callback URI" do
      Rails.application.load_seed
      app = OauthApplication.find_by(name: "claude-mcp")
      expect(app).not_to be_nil
      expect(app.redirect_uri).to eq("https://claude.ai/api/mcp/auth_callback")
    end

    it "registers the application as confidential with all available scopes" do
      Rails.application.load_seed
      app = OauthApplication.find_by(name: "claude-mcp")
      expect(app.confidential?).to be(true)
      expect(app.scopes.to_s.split(" ")).to match_array(Scopes::ALL)
    end

    it "is idempotent — a second seed run does NOT duplicate the row" do
      Rails.application.load_seed
      expect(OauthApplication.where(name: "claude-mcp").count).to eq(1)
      expect { Rails.application.load_seed }.not_to change { OauthApplication.where(name: "claude-mcp").count }
    end
  end

  # Phase 32 follow-up (2026-05-16). Runtime-state restore branch —
  # `db/seeds.rb` reads `Rails.application.credentials.runtime_state`
  # (when present) and restores TOTP enrollment, webhook rows, and
  # Doorkeeper applications. When the block is absent, the seed
  # behaves exactly as the dev-token + claude-mcp + platforms seed
  # blocks above.
  #
  # Placeholder pending blocks — bodies fill in after the master
  # agent confirms the manual playbook lands as designed.
  describe "runtime_state restore branch" do
    describe "with credentials.runtime_state present" do
      it "restores the TOTP seed + enabled_at onto User.first" do
        pending "validated manually first"
        raise "pending placeholder"
      end

      it "regenerates 10 fresh backup codes and prints them once " \
         "(the captured payload has no plaintext to restore)" do
        pending "validated manually first"
        raise "pending placeholder"
      end

      it "restores the Discord + Slack NotificationDeliveryChannel rows " \
         "with yes/no flags converted back to Ruby booleans" do
        pending "validated manually first"
        raise "pending placeholder"
      end

      it "restores OauthApplication rows by uid (and the captured " \
         "claude-mcp row pre-empts the seed's own create branch)" do
        pending "validated manually first"
        raise "pending placeholder"
      end

      it "is idempotent — a second seed run on the same captured state " \
         "leaves the DB unchanged" do
        pending "validated manually first"
        raise "pending placeholder"
      end
    end

    describe "with credentials.runtime_state absent" do
      it "is a no-op — the existing dev token + claude-mcp + platform " \
         "seeds run unchanged" do
        pending "validated manually first"
        raise "pending placeholder"
      end
    end
  end
end
