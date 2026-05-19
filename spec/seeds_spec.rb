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
  describe "runtime_state restore branch" do
    # Shared helper — stubs `Rails.application.credentials` so the seed
    # sees both a valid `:owner` block (otherwise the owner-creation
    # branch falls back to placeholder values + a separate user) AND
    # whichever `runtime_state` payload the spec supplies. `dig` is
    # passed through to the real credentials for everything else
    # (e.g. `:tokens, :pepper` consumed by the dev-token branch).
    def stub_credentials(runtime_state:, owner_username: "owner_rs_#{SecureRandom.hex(2)}")
      original_dig = Rails.application.credentials.method(:dig)
      allow(Rails.application.credentials).to receive(:dig) do |*args|
        if args == [ :owner ]
          { username: owner_username, password: "spec-password-1" }
        else
          original_dig.call(*args)
        end
      end
      allow(Rails.application.credentials).to receive(:runtime_state).and_return(runtime_state)
      owner_username
    end

    # Truncate the surfaces the restore branch writes to so each
    # example begins from a known empty state. The Phase 27 platform
    # seed and the claude-mcp OAuth seed both rebuild on every run, so
    # we wipe + assert post-run rather than carrying fixtures across.
    before do
      User.delete_all
      NotificationDeliveryChannel.delete_all
      OauthApplication.delete_all
    end

    describe "with credentials.runtime_state present" do
      let(:totp_seed)         { "JBSWY3DPEHPK3PXP" }
      let(:totp_enabled_at)   { Time.utc(2026, 5, 1, 12, 30, 0) }
      let(:slack_webhook_url) { "https://hooks.slack.com/services/T01ABCDEFGH/B01ABCDEFGH/abcdefghijklmnopqrstuvwx" }
      let(:discord_webhook_url) { "https://discord.com/api/webhooks/123456789012345678/AbcDefGhiJklMnoPqrStuVwxYz_-AbcDefGhiJklMnoPqrStuVwxYz_-AbcDef" }

      let(:runtime_state_payload) do
        {
          totp: {
            seed:         totp_seed,
            enabled_at:   totp_enabled_at,
            disabled_at:  nil
          },
          webhooks: {
            discord: {
              webhook_url:       discord_webhook_url,
              everything:        "yes",
              daily_digest:      "no",
              last_validated_at: Time.utc(2026, 5, 1, 13, 0, 0)
            },
            slack: {
              webhook_url:       slack_webhook_url,
              everything:        "no",
              daily_digest:      "yes",
              last_validated_at: Time.utc(2026, 5, 1, 13, 5, 0)
            }
          },
          oauth_apps: [
            {
              name:         "claude-mcp",
              uid:          "captured-claude-uid-abc123",
              secret:       "captured-claude-secret-xyz789",
              redirect_uri: "https://claude.ai/api/mcp/auth_callback",
              scopes:       Scopes::ALL.join(" "),
              confidential: "yes"
            }
          ]
        }
      end

      it "restores the TOTP seed + enabled_at onto User.first" do
        stub_credentials(runtime_state: runtime_state_payload)
        silence_stream($stdout) { Rails.application.load_seed }

        owner = User.first
        expect(owner).to be_present
        expect(owner.totp_seed_encrypted).to eq(totp_seed)
        expect(owner.totp_enabled_at).to eq(totp_enabled_at)
        expect(owner.totp_disabled_at).to be_nil
      end

      it "regenerates 10 fresh backup codes and prints them once " \
         "(the captured payload has no plaintext to restore)" do
        stub_credentials(runtime_state: runtime_state_payload)
        fake_codes = Array.new(10) { |i| "BACKUP-CODE-#{i.to_s.rjust(2, '0')}" }
        expect(Auth::BackupCodeRegenerator).to receive(:call)
          .with(hash_including(source_surface: :tui))
          .and_return(fake_codes)

        output = capture_stdout { Rails.application.load_seed }

        fake_codes.each do |code|
          expect(output).to include(code)
        end
        expect(output.scan(fake_codes.first).size).to eq(1)
      end

      it "restores the Discord + Slack NotificationDeliveryChannel rows " \
         "with yes/no flags converted back to Ruby booleans" do
        stub_credentials(runtime_state: runtime_state_payload)
        silence_stream($stdout) { Rails.application.load_seed }

        expect(NotificationDeliveryChannel.count).to eq(2)

        discord = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(discord).to be_present
        expect(discord.webhook_url).to eq(discord_webhook_url)
        expect(discord.everything).to be(true)
        expect(discord.daily_digest).to be(false)

        slack = NotificationDeliveryChannel.find_by(kind: "slack")
        expect(slack).to be_present
        expect(slack.webhook_url).to eq(slack_webhook_url)
        expect(slack.everything).to be(false)
        expect(slack.daily_digest).to be(true)
      end

      it "restores OauthApplication rows by uid (and the captured " \
         "claude-mcp row pre-empts the seed's own create branch)" do
        stub_credentials(runtime_state: runtime_state_payload)
        silence_stream($stdout) { Rails.application.load_seed }

        # Exactly one claude-mcp row — the captured uid won, the seed's
        # own create branch found it by name and skipped its create.
        claude_rows = OauthApplication.where(name: "claude-mcp")
        expect(claude_rows.count).to eq(1)

        claude = OauthApplication.find_by(uid: "captured-claude-uid-abc123")
        expect(claude).to be_present
        expect(claude.name).to eq("claude-mcp")
        expect(claude.secret).to eq("captured-claude-secret-xyz789")
        expect(claude.redirect_uri).to eq("https://claude.ai/api/mcp/auth_callback")
        expect(claude.confidential?).to be(true)
      end

      it "is idempotent for the runtime_state-restored surfaces — a " \
         "second seed run on the same captured state leaves those rows " \
         "unchanged" do
        stub_credentials(runtime_state: runtime_state_payload)
        silence_stream($stdout) { Rails.application.load_seed }

        # Snapshot only the surfaces the runtime_state restore branch is
        # responsible for. The Phase 27 platform seed has a known
        # non-idempotency (the FriendlyId callback rewrites the seed's
        # `slug: "ps5"` to `"playstation-5"` post-save, so the next run's
        # `find_or_create_by!(slug: "ps5")` lookup misses and inserts a
        # second row). That drift is tracked separately from this spec —
        # the contract here is the runtime_state restore branch's own
        # idempotency, not the unrelated platforms seed.
        snapshot = {
          users:                          User.count,
          notification_delivery_channels: NotificationDeliveryChannel.count,
          oauth_applications:             OauthApplication.count,
          api_tokens:                     ApiToken.count
        }

        # Second seed run on the same stubbed state.
        silence_stream($stdout) { Rails.application.load_seed }

        expect(User.count).to eq(snapshot[:users])
        expect(NotificationDeliveryChannel.count).to eq(snapshot[:notification_delivery_channels])
        expect(OauthApplication.count).to eq(snapshot[:oauth_applications])
        expect(ApiToken.count).to eq(snapshot[:api_tokens])
      end
    end

    describe "with credentials.runtime_state absent" do
      it "is a no-op — the existing dev token + claude-mcp + platform " \
         "seeds run unchanged" do
        stub_credentials(runtime_state: nil)
        silence_stream($stdout) { Rails.application.load_seed }

        # The standard seed blocks ran to completion: platforms
        # populated, the claude-mcp OAuth app exists, no webhook /
        # captured-uid restore left any extra rows behind.
        expect(Platform.unscoped.count).to be > 0
        expect(OauthApplication.where(name: "claude-mcp").count).to eq(1)
        expect(NotificationDeliveryChannel.count).to eq(0)

        # Owner user created from the stubbed :owner credentials.
        expect(User.count).to eq(1)
      end
    end
  end

  # Stdout helpers — RSpec's built-in `output(...).to_stdout` matcher
  # only works on a `expect { ... }` block, but several specs above
  # need to BOTH capture the print payload AND make subsequent
  # assertions on the side effects, so we expose `silence_stream` and
  # `capture_stdout` as plain helpers. Both swap `$stdout` for a
  # `StringIO` so the underlying fd stays untouched.
  def silence_stream(_stream)
    real = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = real
  end

  def capture_stdout
    real = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = real
  end
end
