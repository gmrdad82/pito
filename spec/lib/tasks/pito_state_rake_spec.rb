require "rails_helper"
require "rake"
require "tmpdir"
require "fileutils"
require "yaml"

# Spec for `lib/tasks/pito_state.rake` — the runtime-state capture
# rake task that lifts TOTP + webhook + Doorkeeper-application rows
# into `Rails.application.credentials.runtime_state` so a subsequent
# `db:drop db:create db:migrate db:seed` restores them in place.
#
# Phase 32 follow-up (2026-05-16). Original placeholder pending bodies
# replaced with real coverage (2026-05-17): a per-example temp
# `ActiveSupport::EncryptedConfiguration` swaps in for
# `Rails.application.credentials` so the spec never touches the live
# `config/credentials.yml.enc`. Constants are re-stubbed so the
# backup path also lands in the temp dir.
RSpec.describe "pito:state:capture" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/pito_state",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task["pito:state:capture"] }

  before { task.reenable }

  # Per-example temp dir housing the substitute `creds.yml.enc` +
  # `master.key`. The encrypted file is rewritten by the task; the
  # backup files land next to it inside `tmp_dir/backups/`. Both paths
  # are stubbed onto the task module constants so the live install
  # credentials are never read or written.
  let(:tmp_dir)         { Pathname.new(Dir.mktmpdir("pito_state_spec")) }
  let(:content_path)    { tmp_dir.join("creds.yml.enc") }
  let(:key_path)        { tmp_dir.join("master.key") }
  let(:backup_dir)      { tmp_dir.join("backups") }

  # Seed the temp encrypted file with a representative top-level key
  # set so the round-trip verification has something to preserve.
  let(:initial_top_keys_yaml) do
    {
      "postgres"        => { "host" => "x", "port" => 5432 },
      "secret_key_base" => "abc-test-secret",
      "google_oauth"    => { "client_id" => "g-id", "client_secret" => "g-secret" }
    }.to_yaml
  end

  let(:fake_credentials) do
    File.write(key_path, ActiveSupport::EncryptedFile.generate_key)
    cfg = ActiveSupport::EncryptedConfiguration.new(
      config_path: content_path.to_s,
      key_path: key_path.to_s,
      env_key: "PITO_SPEC_NEVER_SET",
      raise_if_missing_key: true
    )
    cfg.write(initial_top_keys_yaml)
    cfg
  end

  before do
    NotificationDeliveryChannel.delete_all
    OauthApplication.delete_all
    User.delete_all

    FileUtils.mkdir_p(backup_dir)
    stub_const("PitoStateCapture::CREDENTIALS_PATH", content_path)
    stub_const("PitoStateCapture::BACKUP_DIR", backup_dir)

    # Force both lookup paths inside the task to the temp config.
    cfg = fake_credentials
    allow(Rails.application).to receive(:credentials).and_return(cfg)
    allow(Rails.application).to receive(:encrypted).and_return(cfg)
  end

  after do
    FileUtils.remove_entry(tmp_dir) if Dir.exist?(tmp_dir)
  end

  # ---------------------------------------------------------------------
  # Fixture helpers
  # ---------------------------------------------------------------------

  let(:totp_seed) { "JBSWY3DPEHPK3PXP" }

  def seed_user(with_totp: true)
    user = User.create!(
      username: "owner",
      password: "password123",
      password_confirmation: "password123"
    )
    if with_totp
      user.update!(
        totp_seed_encrypted: totp_seed,
        totp_enabled_at: Time.utc(2026, 5, 1, 12, 30, 0)
      )
    end
    user
  end

  def seed_webhook(kind, url, last_validated_at: nil, **_legacy_flags_ignored)
    # 2026-05-20 — F3-B-SIMPLIFY-MODEL. The per-brand `everything` /
    # `daily_digest` columns were dropped. `_legacy_flags_ignored`
    # tolerates older callers that still pass them through; the test
    # bodies that need to assert toggle state use
    # `AppSetting.set_notification_toggle!` directly.
    NotificationDeliveryChannel.create!(
      kind:              kind,
      webhook_url:       url,
      last_validated_at: last_validated_at
    )
  end

  def seed_oauth_app(name, redirect: "http://127.0.0.1:9000/cb", scopes: "app")
    OauthApplication.create!(
      name:         name,
      redirect_uri: redirect,
      scopes:       scopes,
      confidential: true
    )
  end

  def read_runtime_state
    yaml = fake_credentials.read
    parsed = YAML.safe_load(yaml, permitted_classes: [ Symbol, Date, Time ]) || {}
    parsed.deep_stringify_keys["runtime_state"]
  end

  def read_top_level_keys
    yaml = fake_credentials.read
    parsed = YAML.safe_load(yaml, permitted_classes: [ Symbol, Date, Time ]) || {}
    parsed.keys.map(&:to_s).sort
  end

  def silence_stdout
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

  # ---------------------------------------------------------------------
  # Happy path — full capture into credentials.runtime_state
  # ---------------------------------------------------------------------

  describe "happy path — full capture into credentials.runtime_state" do
    it "captures TOTP seed + enabled_at into runtime_state.totp" do
      seed_user(with_totp: true)
      silence_stdout { task.invoke }

      rs = read_runtime_state
      expect(rs).to be_a(Hash)
      expect(rs["totp"]).to be_a(Hash)
      expect(rs["totp"]["seed"]).to eq(totp_seed)
      expect(rs["totp"]["enabled_at"]).to eq("2026-05-01T12:30:00Z")
    end

    it "omits enabled_at when nil (Hash.compact applied at capture)" do
      user = seed_user(with_totp: true)
      user.update_columns(totp_enabled_at: nil)

      silence_stdout { task.invoke }

      rs = read_runtime_state
      expect(rs["totp"]).to be_a(Hash)
      expect(rs["totp"]["seed"]).to eq(totp_seed)
      expect(rs["totp"]).not_to have_key("enabled_at")
    end

    it "leaves runtime_state.totp empty when the user has no TOTP enrolled" do
      seed_user(with_totp: false)
      silence_stdout { task.invoke }

      rs = read_runtime_state
      expect(rs["totp"]).to eq({})
    end

    it "captures Discord + Slack webhook URLs (per-brand flags dropped 2026-05-20)" do
      seed_user(with_totp: true)
      seed_webhook(
        "discord",
        "https://discord.com/api/webhooks/12345/abcDEF-_xyz",
        last_validated_at: Time.utc(2026, 5, 14, 8, 0, 0)
      )
      seed_webhook(
        "slack",
        "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567"
      )

      silence_stdout { task.invoke }

      rs = read_runtime_state
      expect(rs["webhooks"]).to be_a(Hash)
      expect(rs["webhooks"]["discord"]).to include(
        "webhook_url"  => "https://discord.com/api/webhooks/12345/abcDEF-_xyz"
      )
      expect(rs["webhooks"]["discord"]["last_validated_at"]).to eq("2026-05-14T08:00:00Z")
      expect(rs["webhooks"]["slack"]).to include(
        "webhook_url"  => "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567"
      )
    end

    it "captures the shared notification toggles into runtime_state.notifications" do
      seed_user(with_totp: true)
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      AppSetting.set_notification_toggle!(:notifications_send_daily_digest, false)

      silence_stdout { task.invoke }

      rs = read_runtime_state
      expect(rs["notifications"]).to include(
        "send_all"          => "yes",
        "send_daily_digest" => "no"
      )
    end

    it "skips webhooks that have a nil/blank webhook_url" do
      seed_user(with_totp: true)
      # Persist a row whose URL was cleared (the "integration cleared" state).
      NotificationDeliveryChannel.create!(kind: "discord", webhook_url: nil)

      silence_stdout { task.invoke }

      rs = read_runtime_state
      expect(rs["webhooks"]).to eq({})
    end

    it "leaves runtime_state.webhooks empty when no webhook rows exist" do
      seed_user(with_totp: true)
      silence_stdout { task.invoke }

      rs = read_runtime_state
      expect(rs["webhooks"]).to eq({})
    end

    it "captures every OauthApplication with plaintext secret + redirect_uri " \
       "+ scopes + confidential flag (yes/no string)" do
      seed_user(with_totp: true)
      app_a = seed_oauth_app("claude-desktop", redirect: "http://127.0.0.1:9001/cb", scopes: "app")
      app_b = seed_oauth_app("alt-client",     redirect: "http://127.0.0.1:9002/cb", scopes: "dev app")

      silence_stdout { task.invoke }

      rs = read_runtime_state
      expect(rs["oauth_apps"]).to be_an(Array)
      expect(rs["oauth_apps"].size).to eq(2)

      first = rs["oauth_apps"].find { |a| a["name"] == "claude-desktop" }
      expect(first).to include(
        "name"         => "claude-desktop",
        "uid"          => app_a.uid,
        "secret"       => app_a.secret,
        "redirect_uri" => "http://127.0.0.1:9001/cb",
        "scopes"       => "app",
        "confidential" => "yes"
      )

      second = rs["oauth_apps"].find { |a| a["name"] == "alt-client" }
      expect(second).to include(
        "uid"    => app_b.uid,
        "secret" => app_b.secret,
        "scopes" => "dev app"
      )
    end

    it "leaves runtime_state.oauth_apps as empty array when no apps exist" do
      seed_user(with_totp: true)
      silence_stdout { task.invoke }

      rs = read_runtime_state
      expect(rs["oauth_apps"]).to eq([])
    end

    it "preserves every other top-level credentials key untouched" do
      seed_user(with_totp: true)
      pre_keys = read_top_level_keys

      silence_stdout { task.invoke }

      post_keys = read_top_level_keys
      expect(post_keys).to include(*pre_keys)
      expect(post_keys).to include("runtime_state")
    end

    it "preserves the VALUES of pre-existing top-level keys (no clobber)" do
      seed_user(with_totp: true)
      silence_stdout { task.invoke }

      yaml = fake_credentials.read
      parsed = YAML.safe_load(yaml, permitted_classes: [ Symbol, Date, Time ]).deep_stringify_keys
      expect(parsed["postgres"]).to eq("host" => "x", "port" => 5432)
      expect(parsed["secret_key_base"]).to eq("abc-test-secret")
      expect(parsed["google_oauth"]).to eq("client_id" => "g-id", "client_secret" => "g-secret")
    end
  end

  # ---------------------------------------------------------------------
  # No User row
  # ---------------------------------------------------------------------

  describe "no User row present" do
    it "exits non-zero with a clear stderr message and writes nothing" do
      # No User seeded.
      original_yaml = fake_credentials.read

      expect {
        expect { task.invoke }.to raise_error(SystemExit) { |e|
          expect(e.status).not_to eq(0)
        }
      }.to output(/no User row present.*Seed the DB first/).to_stderr

      # The encrypted file content is unchanged.
      expect(fake_credentials.read).to eq(original_yaml)
    end
  end

  # ---------------------------------------------------------------------
  # Idempotent re-run
  # ---------------------------------------------------------------------

  describe "idempotent re-run" do
    it "replaces the prior runtime_state block wholesale (no merge)" do
      seed_user(with_totp: true)
      app = seed_oauth_app("first-app")
      silence_stdout { task.invoke }

      # Confirm first run captured the app.
      expect(read_runtime_state["oauth_apps"].map { |a| a["name"] }).to include("first-app")

      # Remove the app, add a different one, re-run.
      app.destroy!
      seed_oauth_app("second-app")
      task.reenable
      silence_stdout { task.invoke }

      names = read_runtime_state["oauth_apps"].map { |a| a["name"] }
      expect(names).to eq([ "second-app" ])
      expect(names).not_to include("first-app")
    end

    it "is safe to invoke repeatedly without drifting other " \
       "credentials keys" do
      seed_user(with_totp: true)

      silence_stdout { task.invoke }
      first_keys = read_top_level_keys

      task.reenable
      silence_stdout { task.invoke }
      second_keys = read_top_level_keys

      task.reenable
      silence_stdout { task.invoke }
      third_keys = read_top_level_keys

      expect(first_keys).to eq(second_keys)
      expect(second_keys).to eq(third_keys)
    end
  end

  # ---------------------------------------------------------------------
  # Operator-facing stdout (NO secret values)
  # ---------------------------------------------------------------------

  describe "operator-facing stdout (NO secret values)" do
    it "prints the captured counts + names + shared toggles only" do
      seed_user(with_totp: true)
      seed_webhook(
        "discord",
        "https://discord.com/api/webhooks/77/secret-payload-xyz"
      )
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      seed_oauth_app("claude-desktop")

      output = capture_stdout { task.invoke }
      expect(output).to include("capturing runtime state from live DB...")
      expect(output).to include("TOTP enrollment present")
      expect(output).to include("webhook[discord]")
      expect(output).to include("send_all=yes")
      expect(output).to include("send_daily_digest=no")
      expect(output).to include("1 Doorkeeper application to capture")
      expect(output).to include("claude-desktop")
    end

    it "uses the singular form for exactly one Doorkeeper application" do
      seed_user(with_totp: true)
      seed_oauth_app("only-one")

      output = capture_stdout { task.invoke }
      expect(output).to include("1 Doorkeeper application to capture")
    end

    it "pluralises for >1 Doorkeeper applications" do
      seed_user(with_totp: true)
      seed_oauth_app("app-one")
      seed_oauth_app("app-two")

      output = capture_stdout { task.invoke }
      expect(output).to include("2 Doorkeeper applications to capture")
    end

    it "prints the IRRECOVERABLE notice for TOTP backup codes + " \
       "dev ApiToken plaintext" do
      seed_user(with_totp: true)

      output = capture_stdout { task.invoke }
      expect(output).to include("IRRECOVERABLE")
      expect(output).to match(/TOTP backup codes.*plaintext gone/)
      expect(output).to match(/dev ApiToken plaintext.*plaintext gone/)
    end

    it "does NOT print the TOTP seed, the webhook URLs, or any OAuth " \
       "client_secret" do
      seed_user(with_totp: true)
      seed_webhook(
        "slack",
        "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567"
      )
      app = seed_oauth_app("claude-desktop")

      output = capture_stdout { task.invoke }

      expect(output).not_to include(totp_seed)
      expect(output).not_to include("https://hooks.slack.com")
      expect(output).not_to include(app.secret)
    end

    it "reports `no TOTP enrollment` when the user is not enrolled" do
      seed_user(with_totp: false)

      output = capture_stdout { task.invoke }
      expect(output).to include("no TOTP enrollment on User.first")
    end

    it "reports `no Discord/Slack webhook rows` when none configured" do
      seed_user(with_totp: true)

      output = capture_stdout { task.invoke }
      expect(output).to include("no Discord/Slack webhook rows")
    end

    it "reports `no Doorkeeper applications` when none registered" do
      seed_user(with_totp: true)

      output = capture_stdout { task.invoke }
      expect(output).to include("no Doorkeeper applications")
    end
  end

  # ---------------------------------------------------------------------
  # Defensive backup + verify pattern
  # ---------------------------------------------------------------------

  describe "defensive backup + verify pattern" do
    it "writes a tmp/credentials.yml.enc.bak-<stamp> copy before mutating " \
       "the live file" do
      seed_user(with_totp: true)
      silence_stdout { task.invoke }

      backups = Dir.glob(backup_dir.join("credentials.yml.enc.bak-*"))
      expect(backups.size).to eq(1)
      stamped = File.basename(backups.first)
      expect(stamped).to match(/\Acredentials\.yml\.enc\.bak-\d{14}\z/)
    end

    it "prints the backup path on success so the operator can locate it" do
      seed_user(with_totp: true)
      output = capture_stdout { task.invoke }
      expect(output).to match(/backup retained at: .*credentials\.yml\.enc\.bak-\d{14}/)
    end

    it "the backup file is byte-identical to the pre-task encrypted content" do
      seed_user(with_totp: true)
      pre_bytes = File.binread(content_path)

      silence_stdout { task.invoke }

      backup_path = Dir.glob(backup_dir.join("credentials.yml.enc.bak-*")).first
      expect(File.binread(backup_path)).to eq(pre_bytes)
    end

    it "restores from the backup if the post-write verify finds the file " \
       "lost a pre-existing top-level key" do
      seed_user(with_totp: true)
      pre_bytes = File.binread(content_path)

      # Simulate a corrupted splice that drops `secret_key_base` by
      # intercepting `splice_runtime_state` and returning a YAML body
      # that's missing one of the pre-existing top-level keys.
      allow(PitoStateCapture).to receive(:splice_runtime_state).and_wrap_original do |_orig, yaml_string, payload|
        parsed = YAML.safe_load(yaml_string, permitted_classes: [ Symbol, Date, Time ]) || {}
        parsed = parsed.deep_stringify_keys
        parsed.delete("secret_key_base")
        parsed["runtime_state"] = payload.deep_stringify_keys
        parsed.to_yaml
      end

      expect {
        expect { task.invoke }.to raise_error(SystemExit) { |e|
          expect(e.status).not_to eq(0)
        }
      }.to output(/capture failed.*credentials restored from backup/).to_stderr

      # The on-disk file is restored to the pre-task bytes.
      expect(File.binread(content_path)).to eq(pre_bytes)
    end

    it "restores from the backup when an exception is raised during the write" do
      seed_user(with_totp: true)
      pre_bytes = File.binread(content_path)

      # Force `splice_runtime_state` to blow up — the rescue path
      # MUST restore from the backup before re-raising via exit 1.
      allow(PitoStateCapture).to receive(:splice_runtime_state)
        .and_raise(StandardError, "boom during splice")

      expect {
        expect { task.invoke }.to raise_error(SystemExit) { |e|
          expect(e.status).not_to eq(0)
        }
      }.to output(/capture failed.*credentials restored from backup.*boom during splice/m).to_stderr

      expect(File.binread(content_path)).to eq(pre_bytes)
    end
  end
end

# Phase 32 follow-up (2026-05-16) — reindex lock escape hatch. Operator
# rake task for the "worker crashed mid-reindex; flag is stuck;
# `/settings` is forever spinning" recovery case. Idempotent.
RSpec.describe "pito:state:clear_reindex_lock" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/pito_state",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task["pito:state:clear_reindex_lock"] }

  before do
    task.reenable
    # Clean the singleton anchor so each example starts from "fresh
    # install" — the model lazily creates the row on first access.
    AppSetting.where(key: AppSetting::SINGLETON_KEY).delete_all
  end

  it "clears AppSetting.reindex_running and reindex_started_at " \
     "and prints a confirmation line" do
    AppSetting.start_reindex!
    expect(AppSetting.reindex_running?).to be(true)
    expect(AppSetting.reindex_started_at).to be_present

    expect { task.invoke }.to output(
      /reindex lock cleared \(reindex_running=false, reindex_started_at=nil\)\./
    ).to_stdout

    expect(AppSetting.reindex_running?).to be(false)
    expect(AppSetting.reindex_started_at).to be_nil
  end

  it "is idempotent — safe to invoke when the lock is already clear" do
    # No prior `start_reindex!` — the singleton row defaults to
    # `reindex_running=false`. The task still completes cleanly.
    expect { task.invoke }.to output(
      /reindex lock cleared/
    ).to_stdout

    expect(AppSetting.reindex_running?).to be(false)
  end

  it "creates the singleton anchor row on first invocation if missing" do
    expect(AppSetting.where(key: AppSetting::SINGLETON_KEY).count).to eq(0)

    expect { task.invoke }.to output(/reindex lock cleared/).to_stdout

    expect(AppSetting.where(key: AppSetting::SINGLETON_KEY).count).to eq(1)
  end

  it "re-running after a real clear keeps the flag false" do
    AppSetting.start_reindex!
    task.invoke
    task.reenable
    capture_io { task.invoke }
    expect(AppSetting.reindex_running?).to be(false)
  end

  def capture_io
    real_out = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = real_out
  end
end
