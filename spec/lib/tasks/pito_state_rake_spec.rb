require "rails_helper"
require "rake"

# Spec for `lib/tasks/pito_state.rake` — the runtime-state capture
# rake task that lifts TOTP + webhook + Doorkeeper-application rows
# into `Rails.application.credentials.runtime_state` so a subsequent
# `db:drop db:create db:migrate db:seed` restores them in place.
#
# Phase 32 follow-up (2026-05-16). Placeholder pending blocks — the
# behavior the master agent will validate manually first; the spec
# bodies fill in once the validation shapes are confirmed.
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

  describe "happy path — full capture into credentials.runtime_state" do
    it "captures TOTP seed + enabled_at into runtime_state.totp" do
      pending "validated manually first; spec fills in after the operator " \
              "confirms the YAML shape lands cleanly in credentials"
      raise "pending placeholder"
    end

    it "captures Discord + Slack webhook URLs + routing flags " \
       "(yes/no strings)" do
      pending "validated manually first; spec fills in after the operator " \
              "confirms the YAML shape lands cleanly in credentials"
      raise "pending placeholder"
    end

    it "captures every OauthApplication with plaintext secret + redirect_uri " \
       "+ scopes + confidential flag (yes/no string)" do
      pending "validated manually first; spec fills in after the operator " \
              "confirms the YAML shape lands cleanly in credentials"
      raise "pending placeholder"
    end

    it "preserves every other top-level credentials key untouched " \
       "(postgres / owner / google_oauth / voyage / tokens / etc.)" do
      pending "validated manually first; spec fills in after the operator " \
              "confirms the YAML shape lands cleanly in credentials"
      raise "pending placeholder"
    end
  end

  describe "no User row present" do
    it "exits non-zero with a clear stderr message and writes nothing" do
      pending "validated manually first"
      raise "pending placeholder"
    end
  end

  describe "idempotent re-run" do
    it "replaces the prior runtime_state block wholesale (no merge)" do
      pending "validated manually first"
      raise "pending placeholder"
    end

    it "is safe to invoke repeatedly without drifting other " \
       "credentials keys" do
      pending "validated manually first"
      raise "pending placeholder"
    end
  end

  describe "operator-facing stdout (NO secret values)" do
    it "prints the captured counts + names + yes/no flags only" do
      pending "validated manually first"
      raise "pending placeholder"
    end

    it "prints the IRRECOVERABLE notice for TOTP backup codes + " \
       "dev ApiToken plaintext" do
      pending "validated manually first"
      raise "pending placeholder"
    end

    it "does NOT print the TOTP seed, the webhook URLs, or any OAuth " \
       "client_secret" do
      pending "validated manually first"
      raise "pending placeholder"
    end
  end

  describe "defensive backup + verify pattern" do
    it "writes a tmp/credentials.yml.enc.bak-<stamp> copy before mutating " \
       "the live file" do
      pending "validated manually first"
      raise "pending placeholder"
    end

    it "restores from the backup if the post-write verify finds the file " \
       "lost a pre-existing top-level key" do
      pending "validated manually first"
      raise "pending placeholder"
    end

    it "restores from the backup if the post-write read fails to decrypt" do
      pending "validated manually first"
      raise "pending placeholder"
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

  before { task.reenable }

  it "clears AppSetting.reindex_running and reindex_started_at " \
     "and prints a confirmation line" do
    pending "validated manually first; spec fills in after the operator " \
            "confirms the rake clears the singleton row in place"
    raise "pending placeholder"
  end

  it "is idempotent — safe to invoke when the lock is already clear" do
    pending "validated manually first"
    raise "pending placeholder"
  end
end
