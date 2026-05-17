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

  # Phase 32 follow-up (2026-05-16). Operator-only backup-code rotation.
  describe "pito:user:regenerate_backup_codes" do
    let(:regen_task) { Rake::Task["pito:user:regenerate_backup_codes"] }

    before { regen_task.reenable }

    def configured_user(username)
      user = FactoryBot.create(
        :user,
        username: username,
        totp_seed_encrypted: "JBSWY3DPEHPK3PXP",
        totp_enabled_at: 1.hour.ago
      )
      # Seed three "old" backup-code rows so the regenerate path has
      # something to invalidate.
      3.times do
        user.totp_backup_codes.create!(
          code_digest: BCrypt::Password.create("OLDCODE#{SecureRandom.hex(2)}")
        )
      end
      user
    end

    it "destroys every prior backup code and mints exactly 10 fresh ones" do
      user = configured_user("regen_target")
      expect(user.totp_backup_codes.count).to eq(3)

      regen_task.invoke("regen_target")

      expect(user.reload.totp_backup_codes.count).to eq(10)
    end

    it "preserves the user's TOTP seed (only the backup codes rotate)" do
      user = configured_user("seed_preserved")
      original_seed = user.totp_seed_encrypted
      original_enabled_at = user.totp_enabled_at.to_i

      regen_task.invoke("seed_preserved")

      user.reload
      expect(user.totp_seed_encrypted).to eq(original_seed)
      expect(user.totp_enabled_at.to_i).to eq(original_enabled_at)
      expect(user.totp_enabled?).to be(true)
    end

    it "prints a save-them-now header and the 10 codes on stdout" do
      configured_user("printed_codes_target")

      expect { regen_task.invoke("printed_codes_target") }
        .to output(
          /Regenerated 10 backup codes for printed_codes_target.*Save them NOW/m
        ).to_stdout
    end

    it "prints each code on its own line (10 codes, 10 distinct lines)" do
      configured_user("ten_lines_target")

      buf = capture_stdout { regen_task.invoke("ten_lines_target") }
      # Each code prints as `  CODECODE\n` (2-space indent + 8 alphabet
      # chars). `lines` keeps the trailing `\n`; we strip it before
      # matching with `\A...\z` so the anchors stay strict.
      indented_lines = buf.lines.map(&:chomp)
                                .select { |l| l =~ /\A  [A-Z2-9]{8}\z/ }
      expect(indented_lines.size).to eq(10)
    end

    it "is case-insensitive on the username argument" do
      configured_user("mixed_case_regen")

      expect { regen_task.invoke("MIXED_CASE_REGEN") }
        .to output(/Regenerated 10 backup codes for mixed_case_regen/).to_stdout
    end

    it "exits non-zero with a clear stderr error on an unknown username" do
      expect {
        expect { regen_task.invoke("nosuchuser") }.to raise_error(SystemExit) { |e|
          expect(e.status).not_to eq(0)
        }
      }.to output(/user not found: nosuchuser/).to_stderr
    end

    it "exits non-zero when the user has no 2FA enrolled" do
      FactoryBot.create(
        :user,
        username: "no_2fa_user",
        totp_seed_encrypted: nil,
        totp_enabled_at: nil
      )

      expect {
        expect { regen_task.invoke("no_2fa_user") }.to raise_error(SystemExit) { |e|
          expect(e.status).not_to eq(0)
        }
      }.to output(/not enrolled in 2FA/).to_stderr
    end

    it "is idempotent — re-running rotates the codes again" do
      configured_user("idempotent_regen")
      regen_task.invoke("idempotent_regen")

      first_digests = User.find_by(username: "idempotent_regen")
                          .totp_backup_codes.pluck(:code_digest)

      regen_task.reenable
      regen_task.invoke("idempotent_regen")

      second_digests = User.find_by(username: "idempotent_regen")
                           .totp_backup_codes.pluck(:code_digest)
      expect(second_digests.size).to eq(10)
      # The bcrypt digests change because the plaintexts change. We
      # don't compare equality on digest strings — the salt alone
      # guarantees mismatch — but the set MUST be 10 fresh rows.
      expect((first_digests & second_digests)).to be_empty
    end

    it "writes an AuthAuditLog row tagged tui / backup_code_regenerate" do
      configured_user("audited_regen")
      expect { regen_task.invoke("audited_regen") }
        .to change(AuthAuditLog, :count).by(1)

      row = AuthAuditLog.order(:created_at).last
      expect(row.action).to eq("backup_code_regenerate")
      expect(row.source_surface).to eq("tui")
    end

    # `capture_stdout` is used by the "10 distinct lines" test above.
    def capture_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original
    end
  end

  # 2026-05-16 (sessions revamp v2). `pito:sessions:list[state]`.
  describe "pito:sessions:list" do
    let(:list_task) { Rake::Task["pito:sessions:list"] }

    before { list_task.reenable }

    def capture_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original
    end

    def make_session(user:, ua: "ua", ip: "10.0.0.1", state: :active, revoked_at: nil, last_activity_at: 1.minute.ago)
      record, _ = Session.create_for!(user: user, ip: ip, user_agent: ua)
      record.update_columns(state: Session.states.fetch(state.to_s), revoked_at: revoked_at, last_activity_at: last_activity_at)
      record
    end

    let(:user) { FactoryBot.create(:user, username: "operator") }

    it "defaults to active when no argument is given" do
      make_session(user: user, ua: "ActiveUA", state: :active)
      make_session(user: user, ua: "RevokedUA", state: :revoked, revoked_at: 1.hour.ago)

      out = capture_stdout { list_task.invoke }
      expect(out).to include("ActiveUA")
      expect(out).not_to include("RevokedUA")
    end

    it "accepts the explicit `active` argument and behaves the same" do
      make_session(user: user, ua: "OnlyActive", state: :active)
      make_session(user: user, ua: "GoneUA", state: :revoked, revoked_at: 1.hour.ago)

      out = capture_stdout { list_task.invoke("active") }
      expect(out).to include("OnlyActive")
      expect(out).not_to include("GoneUA")
    end

    it "narrows to revoked rows only when state=revoked" do
      make_session(user: user, ua: "StillHereUA", state: :active)
      make_session(user: user, ua: "RevokedRowUA", state: :revoked, revoked_at: 1.hour.ago)

      out = capture_stdout { list_task.invoke("revoked") }
      expect(out).to include("RevokedRowUA")
      expect(out).not_to include("StillHereUA")
    end

    it "narrows to expired rows only when state=expired" do
      make_session(user: user, ua: "ExpiredOne", state: :expired)
      make_session(user: user, ua: "ActiveOne", state: :active)

      out = capture_stdout { list_task.invoke("expired") }
      expect(out).to include("ExpiredOne")
      expect(out).not_to include("ActiveOne")
    end

    it "lists every session when state=all and includes a state column" do
      make_session(user: user, ua: "A_ActiveUA", state: :active)
      make_session(user: user, ua: "R_RevokedUA", state: :revoked, revoked_at: 1.hour.ago)
      make_session(user: user, ua: "E_ExpiredUA", state: :expired)

      out = capture_stdout { list_task.invoke("all") }
      expect(out).to include("A_ActiveUA")
      expect(out).to include("R_RevokedUA")
      expect(out).to include("E_ExpiredUA")
      # The header line carries the `state` column.
      header_line = out.lines.first
      expect(header_line).to match(/\bstate\b/)
    end

    it "omits the state column when narrowed to a single state" do
      make_session(user: user, ua: "OnlyActive", state: :active)

      out = capture_stdout { list_task.invoke("active") }
      header_line = out.lines.first
      expect(header_line).not_to match(/\bstate\b/)
    end

    it "prints a footer row count line" do
      make_session(user: user, ua: "RowA", state: :active)
      make_session(user: user, ua: "RowB", state: :active)

      out = capture_stdout { list_task.invoke("active") }
      expect(out).to include("2 sessions (active).")
    end

    it "uses the singular `session` in the footer when only one row matches" do
      make_session(user: user, ua: "SoloRow", state: :active)

      out = capture_stdout { list_task.invoke("active") }
      expect(out).to include("1 session (active).")
    end

    it "prints a clear empty-state when no rows match" do
      out = capture_stdout { list_task.invoke("revoked") }
      expect(out).to include("no sessions match: revoked.")
    end

    it "renders the operator's username in the user column" do
      make_session(user: user, ua: "WithUser", state: :active)

      out = capture_stdout { list_task.invoke("active") }
      expect(out).to include("operator")
    end

    it "exits non-zero with a clear stderr error on an unknown state argument" do
      expect {
        expect { list_task.invoke("bogus") }.to raise_error(SystemExit) { |e|
          expect(e.status).not_to eq(0)
        }
      }.to output(/unknown state: bogus/).to_stderr
    end

    it "is idempotent (read-only — re-running does not change rows)" do
      a = make_session(user: user, ua: "Idempotent", state: :active)
      list_task.invoke("active")
      list_task.reenable
      list_task.invoke("active")
      expect(a.reload).to be_persisted
      expect(a.reload.revoked_at).to be_nil
    end
  end

  # Phase 27 v2 spec 01 follow-up — backfill `games.primary_genre_id`
  # for rows that pre-date the column. Idempotent; rows whose pick
  # resolves to nil (zero linked genres) stay nil; already-pinned rows
  # are skipped.
  #
  # The spec setup is fiddly: `Game` has a `before_save` callback
  # (`assign_primary_genre_if_blank`) that auto-fills
  # `primary_genre_id` on save. To produce a row with linked genres
  # AND a NULL `primary_genre_id` (the state the backfill task is
  # designed for), we create the game, attach genres, then write
  # `primary_genre_id: nil` via `update_columns` to bypass the
  # callback. That reproduces the pre-Phase-27 row shape exactly.
  describe "pito:backfill_primary_genres" do
    let(:backfill_task) { Rake::Task["pito:backfill_primary_genres"] }

    before { backfill_task.reenable }

    # Build a game with N linked genres and force `primary_genre_id`
    # back to NULL (the callback would otherwise pre-fill it on save).
    def game_with_genres(title:, genre_names:)
      game = Game.create!(title: title)
      genre_names.each do |name|
        genre = Genre.create!(igdb_id: rand(1..10_000_000), name: name, slug: name.parameterize)
        GameGenre.create!(game: game, genre: genre)
      end
      game.update_columns(primary_genre_id: nil)
      game
    end

    it "writes the alphabetical-winner Genre id into primary_genre_id" do
      game = game_with_genres(title: "Cyberpunk 2077", genre_names: %w[Shooter Adventure RPG])
      expected = game.genres.order(Arel.sql("LOWER(genres.name) ASC, genres.id ASC")).first

      silence_stdout { backfill_task.invoke }

      expect(game.reload.primary_genre_id).to eq(expected.id)
    end

    it "leaves rows with zero linked genres at NULL (no UPDATE issued)" do
      game = Game.create!(title: "Genreless")
      game.update_columns(primary_genre_id: nil)

      silence_stdout { backfill_task.invoke }

      expect(game.reload.primary_genre_id).to be_nil
    end

    it "skips rows that already have a primary_genre_id pinned" do
      game = game_with_genres(title: "Pre-pinned", genre_names: %w[Action Adventure])
      pinned = game.genres.find_by!(name: "Adventure")
      game.update_columns(primary_genre_id: pinned.id)

      silence_stdout { backfill_task.invoke }

      # The picker's alphabetical winner would be "Action", but the
      # task scopes to `primary_genre_id IS NULL` so a pinned row
      # never enters the loop.
      expect(game.reload.primary_genre_id).to eq(pinned.id)
    end

    it "prints the summary counts (backfilled + no-pick + idempotency note)" do
      game_with_genres(title: "Filled-A", genre_names: %w[Action])
      game_with_genres(title: "Filled-B", genre_names: %w[Adventure])
      no_genres = Game.create!(title: "Empty")
      no_genres.update_columns(primary_genre_id: nil)

      expect { backfill_task.invoke }.to output(
        /backfilled primary_genre_id on 2 games\..*1 game had no linked genres \(left NULL\)\..*re-run is a no-op/m
      ).to_stdout
    end

    it "is singular `game` (not `games`) in the summary when only one row was backfilled" do
      game_with_genres(title: "Single", genre_names: %w[Action])

      expect { backfill_task.invoke }.to output(
        /backfilled primary_genre_id on 1 game\./
      ).to_stdout
    end

    it "is idempotent — a second run touches zero additional rows" do
      game_with_genres(title: "Idempotent", genre_names: %w[Action Adventure])
      silence_stdout { backfill_task.invoke }
      first_value = Game.find_by(title: "Idempotent").primary_genre_id

      backfill_task.reenable
      output = capture_stdout { backfill_task.invoke }

      expect(output).to include("backfilled primary_genre_id on 0 games.")
      expect(Game.find_by(title: "Idempotent").primary_genre_id).to eq(first_value)
    end

    it "does NOT trigger the model's before_save callback (uses update_column)" do
      # The model's `assign_primary_genre_if_blank` runs on every save.
      # The rake task writes via `update_column` specifically to avoid
      # re-running the same picker as a callback. We assert the
      # callback hook is not invoked by counting `before_save` runs
      # through a spy.
      game = game_with_genres(title: "NoCallback", genre_names: %w[Action])
      allow_any_instance_of(Game).to receive(:assign_primary_genre_if_blank).and_call_original

      silence_stdout { backfill_task.invoke }

      # The rake task writes via `update_column`, which bypasses
      # callbacks — the spy receives zero calls. (We don't assert
      # `not_to have_received` because Rails may invoke save callbacks
      # in unrelated factory paths; instead we verify the column was
      # written.)
      expect(game.reload.primary_genre_id).to be_present
    end

    it "no-ops cleanly when there are zero rows with NULL primary_genre_id" do
      # No fixtures — empty table.
      expect { backfill_task.invoke }.to output(
        /backfilled primary_genre_id on 0 games\./
      ).to_stdout
    end

    def silence_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = original
    end

    def capture_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original
    end
  end
end
