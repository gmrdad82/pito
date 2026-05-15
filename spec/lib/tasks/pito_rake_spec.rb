require "rails_helper"
require "rake"

# Spec for `lib/tasks/pito.rake`. The tasks here are one-off operator
# helpers; each spec loads the task file in isolation, reinvokes the
# named task, and asserts on database side effects + the line of stdout
# the task prints.
RSpec.describe "pito rake tasks" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/pito",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task["pito:drop_seeded_channels"] }

  before do
    task.reenable
  end

  def valid_url(i)
    suffix = ("a".."z").to_a[i].to_s * 22
    "https://www.youtube.com/channel/UC#{suffix[0, 22]}"
  end

  describe "pito:drop_seeded_channels" do
    it "deletes channels with NULL youtube_connection_id" do
      Channel.create!(channel_url: valid_url(0), youtube_connection_id: nil)
      Channel.create!(channel_url: valid_url(1), youtube_connection_id: nil)
      expect { task.invoke }.to change { Channel.count }.by(-2)
    end

    it "preserves channels that carry a youtube_connection_id" do
      connection = FactoryBot.create(:youtube_connection)
      kept = Channel.create!(channel_url: valid_url(0),
                             youtube_connection_id: connection.id)
      Channel.create!(channel_url: valid_url(1), youtube_connection_id: nil)
      task.invoke
      expect(Channel.exists?(kept.id)).to be(true)
      expect(Channel.where(youtube_connection_id: nil)).to be_empty
    end

    it "is idempotent — re-running drops zero rows" do
      Channel.create!(channel_url: valid_url(0), youtube_connection_id: nil)
      task.invoke
      task.reenable
      expect { task.invoke }.not_to change { Channel.count }
    end

    it "prints a count line when rows are dropped" do
      Channel.create!(channel_url: valid_url(0), youtube_connection_id: nil)
      Channel.create!(channel_url: valid_url(1), youtube_connection_id: nil)
      expect { task.invoke }.to output(/dropped 2 seeded channels\./).to_stdout
    end

    it "prints a singular count line when one row is dropped" do
      Channel.create!(channel_url: valid_url(0), youtube_connection_id: nil)
      expect { task.invoke }.to output(/dropped 1 seeded channel\./).to_stdout
    end

    it "prints a no-op message when nothing matches" do
      expect { task.invoke }.to output(/no seeded channels to drop\./).to_stdout
    end

    it "cascades through dependent Video rows so no orphans remain" do
      channel = Channel.create!(channel_url: valid_url(0),
                                youtube_connection_id: nil)
      video = Video.create!(channel: channel, youtube_video_id: "abcd1234567")
      task.invoke
      expect(Channel.exists?(channel.id)).to be(false)
      expect(Video.exists?(video.id)).to be(false)
    end
  end

  # Phase 29 — Unit A2 (R2). Operator-only TOTP-reset escape hatch.
  describe "pito:user:reset_totp" do
    let(:reset_task) { Rake::Task["pito:user:reset_totp"] }

    before { reset_task.reenable }

    def configured_user(username)
      user = FactoryBot.create(
        :user,
        username: username,
        totp_seed_encrypted: "JBSWY3DPEHPK3PXP",
        totp_enabled_at: 1.hour.ago
      )
      user.totp_backup_codes.create!(code_digest: BCrypt::Password.create("ABCD2345"))
      Session.create_for!(user: user, ip: "1.2.3.4", user_agent: "x")
      user
    end

    it "clears TOTP enrollment, destroys backup codes, and revokes sessions" do
      user = configured_user("reset_target")
      expect(user.totp_configured?).to be(true)
      expect(user.totp_backup_codes.count).to eq(1)
      expect(user.sessions.count).to eq(1)

      expect { reset_task.invoke("reset_target") }
        .to output(/TOTP reset for reset_target/).to_stdout

      user.reload
      expect(user.totp_seed_encrypted).to be_nil
      expect(user.totp_enabled_at).to be_nil
      expect(user.totp_disabled_at).to be_nil
      expect(user.totp_last_used_step).to be_nil
      expect(user.totp_configured?).to be(false)
      expect(user.totp_backup_codes.count).to eq(0)
      expect(user.sessions.count).to eq(0)
    end

    it "is case-insensitive on the username argument" do
      configured_user("mixed_case")
      expect { reset_task.invoke("MIXED_CASE") }
        .to output(/TOTP reset for mixed_case/).to_stdout
    end

    it "exits non-zero with a clear error on an unknown username" do
      expect {
        expect { reset_task.invoke("nosuchuser") }.to raise_error(SystemExit) { |e|
          expect(e.status).not_to eq(0)
        }
      }.to output(/user not found: nosuchuser/).to_stderr
    end

    it "does not modify any record when the username is unknown" do
      user = configured_user("untouched_user")
      reset_task.reenable
      begin
        reset_task.invoke("ghost")
      rescue SystemExit
        nil
      end
      expect(user.reload.totp_configured?).to be(true)
    end

    it "is idempotent — a second run on an already-cleared user is a no-op-equivalent" do
      configured_user("idempotent_user")
      reset_task.invoke("idempotent_user")

      reset_task.reenable
      expect { reset_task.invoke("idempotent_user") }
        .to output(/TOTP reset for idempotent_user/).to_stdout

      user = User.find_by(username: "idempotent_user")
      expect(user.totp_configured?).to be(false)
      expect(user.totp_backup_codes.count).to eq(0)
      expect(user.sessions.count).to eq(0)
    end

    # Phase 29 — Unit A2 follow-up — security finding F1.
    # The operator-level escape hatch must revoke every bearer
    # credential the user holds — not only their cookie sessions. A
    # user whose TOTP an operator is resetting is, by assumption, a
    # compromised or recovery-mode account; leaking a single ApiToken
    # or Doorkeeper grant past the reset is a false sense of recovery.
    describe "bearer-credential revocation (F1)" do
      let(:oauth_application) { FactoryBot.create(:oauth_application, scopes: Scopes::APP) }

      it "revokes every ApiToken owned by the target user" do
        user = configured_user("rake_token_target")
        record, _plaintext = ApiToken.generate!(
          user: user,
          name: "leaked-token-#{SecureRandom.hex(4)}",
          scopes: [ Scopes::APP ]
        )
        other_user = configured_user("untouched_token_owner")
        other_token, _ = ApiToken.generate!(
          user: other_user,
          name: "other-#{SecureRandom.hex(4)}",
          scopes: [ Scopes::APP ]
        )

        reset_task.invoke("rake_token_target")

        expect(record.reload.revoked?).to be(true)
        expect(record.reload.revoked_at).to be_within(5.seconds).of(Time.current)
        expect(other_token.reload.revoked?).to be(false)
      end

      it "preserves already-revoked ApiToken `revoked_at` (does not re-stamp)" do
        user = configured_user("rake_already_revoked")
        record, _ = ApiToken.generate!(
          user: user,
          name: "already-revoked-#{SecureRandom.hex(4)}",
          scopes: [ Scopes::APP ]
        )
        old_stamp = 1.day.ago.change(usec: 0)
        record.update_columns(revoked_at: old_stamp)

        reset_task.invoke("rake_already_revoked")

        expect(record.reload.revoked_at.to_i).to eq(old_stamp.to_i)
      end

      it "revokes every Doorkeeper::AccessToken owned by the target user" do
        user = configured_user("rake_oauth_target")
        token = Doorkeeper::AccessToken.create!(
          application: oauth_application,
          resource_owner_id: user.id,
          scopes: Scopes::APP,
          expires_in: 7200
        )
        other_user = configured_user("rake_oauth_untouched")
        other_token = Doorkeeper::AccessToken.create!(
          application: oauth_application,
          resource_owner_id: other_user.id,
          scopes: Scopes::APP,
          expires_in: 7200
        )

        reset_task.invoke("rake_oauth_target")

        expect(token.reload.revoked?).to be(true)
        expect(other_token.reload.revoked?).to be(false)
      end

      it "revokes every Doorkeeper::AccessGrant owned by the target user" do
        user = configured_user("rake_grant_target")
        grant = Doorkeeper::AccessGrant.create!(
          application: oauth_application,
          resource_owner_id: user.id,
          token: SecureRandom.hex(32),
          redirect_uri: "http://127.0.0.1:8765/callback",
          scopes: Scopes::APP,
          expires_in: 600
        )

        reset_task.invoke("rake_grant_target")

        expect(grant.reload.revoked?).to be(true)
      end

      it "writes an AuthAuditLog row with revocation tallies + the rake source tag" do
        user = configured_user("rake_audited_target")
        ApiToken.generate!(user: user, name: "audited-1", scopes: [ Scopes::APP ])
        Doorkeeper::AccessToken.create!(
          application: oauth_application,
          resource_owner_id: user.id,
          scopes: Scopes::APP,
          expires_in: 7200
        )
        Doorkeeper::AccessGrant.create!(
          application: oauth_application,
          resource_owner_id: user.id,
          token: SecureRandom.hex(32),
          redirect_uri: "http://127.0.0.1:8765/callback",
          scopes: Scopes::APP,
          expires_in: 600
        )

        expect { reset_task.invoke("rake_audited_target") }
          .to change(AuthAuditLog, :count).by(1)

        row = AuthAuditLog.order(:created_at).last
        expect(row.action).to eq("password_reset")
        expect(row.source_surface).to eq("tui")
        expect(row.acting_user_id).to eq(user.id)
        expect(row.target_id).to eq(user.id)
        meta = row.metadata
        expect(meta["source"]).to eq("rake:pito:user:reset_totp")
        expect(meta["api_tokens_revoked"]).to eq(1)
        expect(meta["oauth_access_tokens_revoked"]).to eq(1)
        expect(meta["oauth_access_grants_revoked"]).to eq(1)
      end

      it "prints the revocation tallies on the success line" do
        user = configured_user("rake_print_target")
        ApiToken.generate!(user: user, name: "p1", scopes: [ Scopes::APP ])
        Doorkeeper::AccessToken.create!(
          application: oauth_application,
          resource_owner_id: user.id,
          scopes: Scopes::APP,
          expires_in: 7200
        )

        expect { reset_task.invoke("rake_print_target") }
          .to output(/api_tokens=1/).to_stdout
      end
    end
  end
end
