require "rails_helper"

# P25 — F12. Boot-time precompute of the dummy BCrypt hash used by
# `SessionsController#bcrypt_dummy_compare`. The initializer at
# `config/initializers/sessions_dummy_bcrypt.rb` runs once at Rails
# boot; by the time these specs execute the constants below must be
# defined and populated with a valid BCrypt hash.
RSpec.describe "Sessions::DUMMY_BCRYPT_HASH boot precompute" do
  it "Sessions::DUMMY_BCRYPT_HASH is populated at boot (NOT nil, NOT computed lazily)" do
    expect(defined?(Sessions::DUMMY_BCRYPT_HASH)).to eq("constant")
    expect(Sessions::DUMMY_BCRYPT_HASH).to be_a(String)
    expect(Sessions::DUMMY_BCRYPT_HASH).not_to be_empty
  end

  it "is a valid BCrypt password hash" do
    # `BCrypt::Password.new(<hash>)` raises `BCrypt::Errors::InvalidHash`
    # on a non-bcrypt string. Constructing it cleanly is the contract.
    expect {
      BCrypt::Password.new(Sessions::DUMMY_BCRYPT_HASH)
    }.not_to raise_error
  end

  it "verifies against Sessions::DUMMY_BCRYPT_PLAINTEXT" do
    hash = BCrypt::Password.new(Sessions::DUMMY_BCRYPT_HASH)
    expect(hash.is_password?(Sessions::DUMMY_BCRYPT_PLAINTEXT)).to be true
  end

  it "is frozen so a downstream caller cannot rebind it per-request" do
    expect(Sessions::DUMMY_BCRYPT_HASH).to be_frozen
    expect(Sessions::DUMMY_BCRYPT_PLAINTEXT).to be_frozen
  end

  it "uses the same cost selection as ActiveModel::SecurePassword" do
    expected_cost =
      if ActiveModel::SecurePassword.min_cost
        BCrypt::Engine::MIN_COST
      else
        BCrypt::Engine.cost
      end
    expect(Sessions::DUMMY_BCRYPT_COST).to eq(expected_cost)
    expect(BCrypt::Password.new(Sessions::DUMMY_BCRYPT_HASH).cost).to eq(expected_cost)
  end

  describe "controller integration" do
    it "SessionsController#bcrypt_dummy_compare reads the boot-time constant (no lazy ivar)" do
      # The lazy `@dummy_bcrypt_hash ||= ...` pattern is gone. Confirm no
      # class-level memoization survives that could re-introduce the
      # first-request timing skew.
      expect(SessionsController).not_to respond_to(:dummy_bcrypt_hash)
      expect(SessionsController).not_to respond_to(:dummy_bcrypt_cost)
    end
  end
end
