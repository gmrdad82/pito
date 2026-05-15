# Phase 29 — Unit A2 follow-up — security finding F6.
#
# Shared helper that runs the constant-ish-time BCrypt compare used by
# the login and password-reset surfaces to symmetrize wall-clock cost
# between "real verification" branches and "bail" branches (unknown
# user, no-TOTP, wrong-shape input). Previously this method was
# duplicated verbatim in `SessionsController` and
# `PasswordResetsController`; a future edit to one and not the other
# would silently introduce a timing asymmetry between the two
# surfaces. Centralizing it into a concern eliminates that drift risk
# and provides a single call site for the F2 fix to attach to.
#
# The hash + plaintext are precomputed at boot by
# `config/initializers/sessions_dummy_bcrypt.rb` (constants
# `Sessions::DUMMY_BCRYPT_HASH` + `Sessions::DUMMY_BCRYPT_PLAINTEXT`)
# so every request — first or thousandth, cold Puma or warm — pays the
# same compare cost. See that initializer for the rationale.
#
# Usage:
#
#     class SessionsController < ApplicationController
#       include Sessions::BcryptDummyCompare
#       # ...
#       bcrypt_dummy_compare
#     end
#
# Always returns `nil` — the value of the BCrypt compare is uninteresting;
# callers want only the side effect (the wall-clock cost).
module Sessions
  module BcryptDummyCompare
    extend ActiveSupport::Concern

    private

    def bcrypt_dummy_compare
      BCrypt::Password.new(Sessions::DUMMY_BCRYPT_HASH).is_password?(
        Sessions::DUMMY_BCRYPT_PLAINTEXT
      )
      nil
    end
  end
end
