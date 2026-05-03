require "rails_helper"

RSpec.describe User, type: :model do
  subject { build(:user) }

  describe "associations" do
    it { is_expected.to belong_to(:tenant) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:username) }
    it { is_expected.to validate_presence_of(:email) }

    describe "username regex" do
      %w[asdk123 M23kony X abc].each do |valid|
        it "accepts #{valid.inspect}" do
          user = build(:user, username: valid)
          expect(user).to be_valid, "expected #{valid.inspect} to be valid: #{user.errors.full_messages}"
        end
      end

      [
        "123abc",            # starts with a digit
        "Catalin Ilinca",    # contains space
        "me_too",            # contains underscore
        "user-name",         # contains hyphen
        "name!",             # contains punctuation
        "",                  # empty
        " username",         # leading space
        "username "          # trailing space
      ].each do |bad|
        it "rejects #{bad.inspect}" do
          user = build(:user, username: bad)
          expect(user).not_to be_valid
          expect(user.errors[:username]).to be_present
        end
      end
    end

    describe "username uniqueness (globally unique across tenants)" do
      it "rejects two users with the same username even in different tenants" do
        tenant_a = create(:tenant)
        tenant_b = create(:tenant)
        create(:user, tenant: tenant_a, username: "shared", email: "a@example.test")
        dup = build(:user, tenant: tenant_b, username: "shared", email: "b@example.test")

        expect(dup).not_to be_valid
        expect(dup.errors[:username]).to be_present
      end

      it "is case-insensitive (citext)" do
        tenant = create(:tenant)
        create(:user, tenant: tenant, username: "MixedCase", email: "a@example.test")
        dup = build(:user, tenant: tenant, username: "mixedcase", email: "b@example.test")

        expect(dup).not_to be_valid
        expect(dup.errors[:username]).to be_present
      end
    end

    describe "email uniqueness (globally unique across tenants)" do
      it "rejects two users with the same email even in different tenants" do
        tenant_a = create(:tenant)
        tenant_b = create(:tenant)
        create(:user, tenant: tenant_a, username: "alpha", email: "shared@example.test")
        dup = build(:user, tenant: tenant_b, username: "beta", email: "shared@example.test")

        expect(dup).not_to be_valid
        expect(dup.errors[:email]).to be_present
      end
    end

    describe "email format" do
      it "rejects invalid emails" do
        expect(build(:user, email: "not-an-email")).not_to be_valid
      end
    end
  end

  describe "has_secure_password" do
    it "round-trips the password through password_digest" do
      user = create(:user, password: "supersecret", password_confirmation: "supersecret")
      expect(user.password_digest).to be_present
      expect(user.authenticate("supersecret")).to eq(user)
      expect(user.authenticate("wrong")).to be(false)
    end
  end

  describe ".find_by_username_or_email" do
    let!(:user) { create(:user, username: "alice", email: "alice@example.test") }

    it "finds by username" do
      expect(User.find_by_username_or_email("alice")).to eq(user)
    end

    it "finds by email" do
      expect(User.find_by_username_or_email("alice@example.test")).to eq(user)
    end

    it "is case-insensitive on username (citext)" do
      expect(User.find_by_username_or_email("ALICE")).to eq(user)
    end

    it "is case-insensitive on email (citext)" do
      expect(User.find_by_username_or_email("ALICE@EXAMPLE.TEST")).to eq(user)
    end

    it "strips surrounding whitespace" do
      expect(User.find_by_username_or_email("  alice  ")).to eq(user)
    end

    it "returns nil for unknown login" do
      expect(User.find_by_username_or_email("nope")).to be_nil
    end

    it "returns nil for blank input" do
      expect(User.find_by_username_or_email("")).to be_nil
      expect(User.find_by_username_or_email(nil)).to be_nil
      expect(User.find_by_username_or_email("   ")).to be_nil
    end
  end
end
