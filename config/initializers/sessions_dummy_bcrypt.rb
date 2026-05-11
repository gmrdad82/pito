# P25 — F12. Boot-time precompute of the dummy BCrypt hash that
# `SessionsController#bcrypt_dummy_compare` uses to symmetrize the wall
# time of a "no such user" branch with `User#authenticate`.
#
# Before this initializer, the hash was lazily memoized on first failed
# login per process — meaning the FIRST failed login paid the
# `BCrypt::Password.create(..., cost: 12)` cost (~250 ms in production)
# while subsequent failed logins paid only the cheap `is_password?`
# compare. That timing difference between first and subsequent failed
# logins is itself an oracle (it shifts the request profile of cold
# Pumas vs warm Pumas in a way an attacker can probe).
#
# Computing the hash at boot moves that cost into Puma startup, where
# every request — first or thousandth — sees identical compare time.
# Production restart cost: ~250 ms per Puma worker; one-time, on a
# path the operator already expects to be slow.
#
# Cost selection mirrors `ActiveModel::SecurePassword`'s logic so the
# dummy compare's wall time stays in lockstep with `User#authenticate`
# under both `min_cost = true` (test speed switch) and `min_cost = false`
# (production default cost 12).
require "bcrypt"

module Sessions
  DUMMY_BCRYPT_COST =
    if ActiveModel::SecurePassword.min_cost
      BCrypt::Engine::MIN_COST
    else
      BCrypt::Engine.cost
    end

  DUMMY_BCRYPT_PLAINTEXT = "dummy-password-noop".freeze

  DUMMY_BCRYPT_HASH = BCrypt::Password.create(
    DUMMY_BCRYPT_PLAINTEXT,
    cost: DUMMY_BCRYPT_COST
  ).to_s.freeze
end
