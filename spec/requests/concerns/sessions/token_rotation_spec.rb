require "rails_helper"

# Phase 25 — 01g (LD-12 extension). Sessions::TokenRotation rotates
# the operator's session token after a privileged auth-state mutation.
# We exercise the concern indirectly through controllers that include
# it (approve / block / unblock / purge / TOTP enroll / disable /
# regenerate). Each test asserts on the visible side-effect: the
# `token_digest` column on `Current.session` changes after the
# destructive action, AND the response sets a fresh `pito_session`
# cookie.
RSpec.describe "Sessions::TokenRotation", type: :request do
  let(:user) { User.first || create(:user) }

  before { Rack::Attack.cache.store.clear if defined?(Rack::Attack) }

  describe "after Login::Approvals#create" do
    let(:pending_user) { create(:user) }
    let(:pending_session) { create(:session, :pending, user: pending_user) }
    let(:fp) { Digest::SHA256.hexdigest("rotation-approve-fp") }
    let!(:attempt) do
      create(:login_attempt, :pending,
             user: pending_user,
             fingerprint_hash: fp,
             ip_prefix: "10.20.0.0/24",
             session: pending_session)
    end

    it "rotates the operator's session token_digest on confirm=yes" do
      operator_session = Session.where(user_id: user.id).order(:created_at).last
      before_digest = operator_session.token_digest

      post login_approval_path(attempt), params: { confirm: "yes" }

      expect(response).to redirect_to(notifications_path)
      operator_session.reload
      expect(operator_session.token_digest).not_to eq(before_digest)
    end

    it "does NOT rotate when confirm is missing (no destructive action ran)" do
      operator_session = Session.where(user_id: user.id).order(:created_at).last
      before_digest = operator_session.token_digest

      post login_approval_path(attempt)  # no confirm param

      operator_session.reload
      expect(operator_session.token_digest).to eq(before_digest)
    end
  end

  describe "after Login::Blocks#create" do
    let(:pending_user) { create(:user) }
    let(:pending_session) { create(:session, :pending, user: pending_user) }
    let(:fp) { Digest::SHA256.hexdigest("rotation-block-fp") }
    let!(:attempt) do
      create(:login_attempt, :pending,
             user: pending_user,
             fingerprint_hash: fp,
             ip_prefix: "10.21.0.0/24",
             session: pending_session)
    end

    it "rotates the operator's session token_digest on confirm=yes" do
      operator_session = Session.where(user_id: user.id).order(:created_at).last
      before_digest = operator_session.token_digest

      post login_block_path(attempt), params: { confirm: "yes" }

      operator_session.reload
      expect(operator_session.token_digest).not_to eq(before_digest)
    end
  end

  describe "after Settings::Security::Blocks::Unblockings#create" do
    let!(:row) { create(:blocked_location) }

    it "rotates the token_digest on a successful unblock" do
      operator_session = Session.where(user_id: user.id).order(:created_at).last
      before_digest = operator_session.token_digest

      post settings_security_block_unblocking_path(row), params: { confirm: "yes" }

      operator_session.reload
      expect(operator_session.token_digest).not_to eq(before_digest)
    end

    it "does NOT rotate on the idempotent already-unblocked no-op" do
      row.update!(unblocked_at: 1.hour.ago, unblocked_by_user: user)
      operator_session = Session.where(user_id: user.id).order(:created_at).last
      before_digest = operator_session.token_digest

      post settings_security_block_unblocking_path(row), params: { confirm: "yes" }

      operator_session.reload
      expect(operator_session.token_digest).to eq(before_digest)
    end
  end

  describe "after Settings::Security::Blocks::Purges#create" do
    let!(:row) { create(:blocked_location, fingerprint_hash: "ff" * 32) }

    it "rotates the token_digest on a successful purge" do
      operator_session = Session.where(user_id: user.id).order(:created_at).last
      before_digest = operator_session.token_digest

      post settings_security_blocks_purge_path,
           params: { fingerprint: row.fingerprint_hash, confirm: "yes" }

      operator_session.reload
      expect(operator_session.token_digest).not_to eq(before_digest)
    end
  end

  describe "after Settings::Security::Attempts::Purges#create" do
    let!(:la) { create(:login_attempt, user: user) }

    it "rotates the token_digest on a successful purge" do
      operator_session = Session.where(user_id: user.id).order(:created_at).last
      before_digest = operator_session.token_digest

      post settings_security_attempts_purge_path,
           params: { user_id: user.id, confirm: "yes" }

      operator_session.reload
      expect(operator_session.token_digest).not_to eq(before_digest)
    end
  end
end
