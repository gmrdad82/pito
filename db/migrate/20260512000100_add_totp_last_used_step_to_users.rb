# Phase 25 follow-up — F9. TOTP replay defense.
#
# RFC 6238 §5.2 mandates that a successfully verified OTP must NOT
# accept the SAME code a second time within the validity window —
# otherwise an attacker who observes a 6-digit code on the wire (or
# over a shoulder) inside the same 30-second drift window can replay
# it.
#
# `users.totp_last_used_step` carries the Unix-time / 30 step index of
# the most recently accepted TOTP code. The verifier (a) computes the
# step ROTP matched, (b) rejects when the new step is `<=` the last
# step recorded for this user, (c) updates this column on a successful
# verify. The column is a `bigint` because the step is bounded by
# `Time.now.to_i / 30` — comfortable in `int4` today but `bigint` is
# the future-proof choice and matches PG's native `bigint` size.
#
# Nullable + default `nil`: a freshly enrolled user has never used a
# code, so the comparison is "new step is non-nil" → always accept on
# first use.
class AddTotpLastUsedStepToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :totp_last_used_step, :bigint
  end
end
