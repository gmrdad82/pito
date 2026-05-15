require "rails_helper"

# Phase 29 — Unit A2 follow-up — security finding F6.
#
# The shared concern that extracts `bcrypt_dummy_compare` from
# `SessionsController` + `PasswordResetsController`. Prior to F6 the
# method body was duplicated verbatim across both controllers, and a
# future edit to one and not the other risked introducing wall-clock
# timing asymmetry between the two surfaces.
#
# These specs anchor:
#
#   1. The concern is `private` (callers must `include` it; the method
#      is not invocable from outside the controller it's mixed into).
#   2. The compare runs against the boot-time precomputed constants on
#      `Sessions::DUMMY_BCRYPT_HASH` + `Sessions::DUMMY_BCRYPT_PLAINTEXT`.
#   3. Both controllers that need symmetric wall-clock cost include the
#      concern — `SessionsController` and `PasswordResetsController`.
RSpec.describe Sessions::BcryptDummyCompare do
  # A minimal includer to exercise the concern in isolation.
  let(:includer_class) do
    Class.new do
      include Sessions::BcryptDummyCompare
      def run! = bcrypt_dummy_compare
    end
  end

  let(:includer) { includer_class.new }

  it "is a Module that can be included" do
    expect(described_class).to be_a(Module)
  end

  it "defines `bcrypt_dummy_compare` as a private instance method" do
    expect(includer_class.private_method_defined?(:bcrypt_dummy_compare)).to be(true)
    expect(includer_class.method_defined?(:bcrypt_dummy_compare)).to be(false)
  end

  it "returns nil — the BCrypt compare value is not part of the contract" do
    expect(includer.send(:bcrypt_dummy_compare)).to be_nil
  end

  it "exercises the boot-time precomputed dummy hash + plaintext" do
    # Pin the compare call site so a future refactor that swaps the
    # constants out (or stops calling `is_password?`) is caught.
    expect_any_instance_of(BCrypt::Password)
      .to receive(:is_password?)
      .with(Sessions::DUMMY_BCRYPT_PLAINTEXT)
      .and_call_original

    includer.send(:bcrypt_dummy_compare)
  end

  it "the BCrypt compare is true when run against the matched plaintext" do
    # Sanity check — the boot-time constants are coherent (plaintext
    # hashes to the precomputed hash). A regression here would silently
    # break the symmetrization invariant.
    hash = BCrypt::Password.new(Sessions::DUMMY_BCRYPT_HASH)
    expect(hash.is_password?(Sessions::DUMMY_BCRYPT_PLAINTEXT)).to be(true)
  end

  describe "controllers that include the concern" do
    it "SessionsController includes the shared concern" do
      expect(SessionsController.include?(Sessions::BcryptDummyCompare)).to be(true)
    end

    it "PasswordResetsController includes the shared concern" do
      expect(PasswordResetsController.include?(Sessions::BcryptDummyCompare)).to be(true)
    end

    it "SessionsController exposes `bcrypt_dummy_compare` as a private method" do
      expect(SessionsController.private_method_defined?(:bcrypt_dummy_compare)).to be(true)
    end

    it "PasswordResetsController exposes `bcrypt_dummy_compare` as a private method" do
      expect(PasswordResetsController.private_method_defined?(:bcrypt_dummy_compare)).to be(true)
    end

    it "the in-controller method is NOT duplicated locally (it comes from the concern)" do
      # If a future edit re-introduces a local `bcrypt_dummy_compare`
      # method on either controller, the owning module for the
      # method-resolution lookup will no longer be the shared concern.
      sessions_owner = SessionsController.instance_method(:bcrypt_dummy_compare).owner
      reset_owner    = PasswordResetsController.instance_method(:bcrypt_dummy_compare).owner

      expect(sessions_owner).to eq(Sessions::BcryptDummyCompare)
      expect(reset_owner).to eq(Sessions::BcryptDummyCompare)
    end
  end
end
