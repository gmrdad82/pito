# frozen_string_literal: true

require "rails_helper"

# Contract for the hand-rolled OAuth 2.1 model layer (G130): registration, the
# single-use PKCE-bound code, and the digest-only token pair. The security
# invariants (no raw secret at rest, single-use, timing-safe, refresh-never-
# expires, revocation) are pinned here; the endpoints spec covers the HTTP flow.
RSpec.describe "OAuth models", type: :model do
  def pkce_pair
    verifier  = SecureRandom.urlsafe_base64(48)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    [ verifier, challenge ]
  end

  describe Pito::Mcp::Oauth do
    it "pkce_matches? verifies base64url(sha256(verifier)) == challenge" do
      verifier, challenge = pkce_pair
      expect(described_class.pkce_matches?(verifier: verifier, challenge: challenge)).to be(true)
      expect(described_class.pkce_matches?(verifier: "wrong", challenge: challenge)).to be(false)
    end

    it "secure_equal? is false on a length mismatch (never raises)" do
      expect(described_class.secure_equal?("abc", "abcd")).to be(false)
      expect(described_class.secure_equal?("abc", "abc")).to be(true)
    end
  end

  describe OauthClient do
    subject(:client) { OauthClient.register(name: "claude.ai", redirect_uris: [ "https://claude.ai/cb" ]) }

    it "mints a client_id and stores no secret" do
      expect(client.client_id).to be_present
      expect(client).not_to respond_to(:client_secret)
    end

    it "allows only an EXACT registered redirect URI (no open redirect)" do
      expect(client.allows_redirect?("https://claude.ai/cb")).to be(true)
      expect(client.allows_redirect?("https://claude.ai/cb/evil")).to be(false)
      expect(client.allows_redirect?("https://evil.example/cb")).to be(false)
    end
  end

  describe OauthCode do
    let(:client) { OauthClient.register(name: "c", redirect_uris: [ "https://c/cb" ]) }

    def mint
      _, challenge = @verifier_challenge = pkce_pair
      OauthCode.mint(client_id: client.client_id, redirect_uri: "https://c/cb", code_challenge: challenge)
    end

    it "stores only the code digest, never the raw code" do
      raw, code = mint
      expect(code.code_digest).not_to eq(raw)
      expect(code.code_digest).to eq(Digest::SHA256.hexdigest(raw))
    end

    it "claims exactly once (single-use); a replay finds nothing" do
      raw, = mint
      expect(OauthCode.claim(raw)).to be_present
      expect(OauthCode.claim(raw)).to be_nil
    end

    it "does not claim an expired code" do
      raw, code = mint
      code.update!(expires_at: 1.minute.ago)
      expect(OauthCode.claim(raw)).to be_nil
    end

    it "valid_exchange? requires the right client, redirect, and PKCE verifier" do
      raw, = mint
      verifier, = @verifier_challenge
      code = OauthCode.claim(raw)

      expect(code.valid_exchange?(client_id: client.client_id, redirect_uri: "https://c/cb", code_verifier: verifier)).to be(true)
      expect(code.valid_exchange?(client_id: "other", redirect_uri: "https://c/cb", code_verifier: verifier)).to be(false)
      expect(code.valid_exchange?(client_id: client.client_id, redirect_uri: "https://c/evil", code_verifier: verifier)).to be(false)
      expect(code.valid_exchange?(client_id: client.client_id, redirect_uri: "https://c/cb", code_verifier: "wrong")).to be(false)
    end
  end

  describe OauthToken do
    let(:client) { OauthClient.register(name: "c", redirect_uris: [ "https://c/cb" ]) }

    it "stores only digests, never the raw tokens" do
      access, refresh, record = OauthToken.issue(client_id: client.client_id)
      expect(record.token_digest).to eq(Digest::SHA256.hexdigest(access))
      expect(record.refresh_digest).to eq(Digest::SHA256.hexdigest(refresh))
      expect(record.token_digest).not_to eq(access)
    end

    it "authenticates a valid access token and rejects an unknown one" do
      access, _, record = OauthToken.issue(client_id: client.client_id)
      expect(OauthToken.authenticate(access)&.id).to eq(record.id)
      expect(OauthToken.authenticate("nope")).to be_nil
      expect(OauthToken.authenticate(nil)).to be_nil
    end

    it "rejects an expired access token" do
      access, _, record = OauthToken.issue(client_id: client.client_id)
      record.update!(expires_at: 1.minute.ago)
      expect(OauthToken.authenticate(access)).to be_nil
    end

    it "rotates the access token on refresh (old dies, refresh survives)" do
      access, refresh, record = OauthToken.issue(client_id: client.client_id)
      new_access, = OauthToken.refresh!(refresh)

      expect(new_access).not_to eq(access)
      expect(OauthToken.authenticate(new_access)&.id).to eq(record.id)
      expect(OauthToken.authenticate(access)).to be_nil
    end

    it "refreshes even after the access token expired (refresh never expires)" do
      _, refresh, record = OauthToken.issue(client_id: client.client_id)
      record.update!(expires_at: 1.hour.ago)
      new_access, = OauthToken.refresh!(refresh)
      expect(OauthToken.authenticate(new_access)).to be_present
    end

    it "revocation kills both the access token and refresh" do
      _, refresh, record = OauthToken.issue(client_id: client.client_id)
      new_access, = OauthToken.refresh!(refresh)
      record.update!(revoked_at: Time.current)

      expect(OauthToken.authenticate(new_access)).to be_nil
      expect(OauthToken.refresh!(refresh)).to be_nil
    end
  end

  describe "Pito::Mcp::Auth.authenticate (the Bearer seam)" do
    it "resolves a valid access token and rejects everything else" do
      client = OauthClient.register(name: "c", redirect_uris: [ "https://c/cb" ])
      access, = OauthToken.issue(client_id: client.client_id)
      expect(Pito::Mcp::Auth.authenticate(access)).to be_present
      expect(Pito::Mcp::Auth.authenticate("bogus")).to be_nil
    end
  end
end
