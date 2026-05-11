require "rails_helper"

RSpec.describe Auth::FingerprintComposer do
  describe ".call" do
    let(:full_inputs) do
      {
        user_agent: "Mozilla/5.0 (Macintosh) Safari/17",
        accept: "text/html,application/xhtml+xml",
        accept_language: "en-US,en;q=0.9",
        accept_encoding: "gzip, deflate, br",
        sec_ch_ua_platform: '"macOS"',
        sec_ch_ua_mobile: "?0",
        screen_hint: "2560x1440@2",
        locale_hint: "Europe/Bucharest/en-US"
      }
    end

    it "happy: returns a 64-char SHA256 hex digest from a full set of inputs" do
      hash = described_class.call(**full_inputs)
      expect(hash).to be_a(String)
      expect(hash.length).to eq(64)
      expect(hash).to match(/\A[a-f0-9]{64}\z/)
    end

    it "is deterministic — same inputs → same hash" do
      h1 = described_class.call(**full_inputs)
      h2 = described_class.call(**full_inputs)
      expect(h1).to eq(h2)
    end

    it "kwarg order does not matter (composer pins canonical ordering)" do
      same_inputs_reversed = {
        locale_hint: full_inputs[:locale_hint],
        screen_hint: full_inputs[:screen_hint],
        sec_ch_ua_mobile: full_inputs[:sec_ch_ua_mobile],
        sec_ch_ua_platform: full_inputs[:sec_ch_ua_platform],
        accept_encoding: full_inputs[:accept_encoding],
        accept_language: full_inputs[:accept_language],
        accept: full_inputs[:accept],
        user_agent: full_inputs[:user_agent]
      }
      expect(described_class.call(**full_inputs))
        .to eq(described_class.call(**same_inputs_reversed))
    end

    it "sad: missing UA composes with empty string (no crash)" do
      hash = described_class.call(**full_inputs.merge(user_agent: nil))
      expect(hash.length).to eq(64)
    end

    it "edge: dropping one header changes the hash" do
      h_full = described_class.call(**full_inputs)
      h_dropped = described_class.call(**full_inputs.merge(accept_encoding: nil))
      expect(h_full).not_to eq(h_dropped)
    end

    it "edge: emoji + non-ASCII in Accept-Language still hashes" do
      inputs = full_inputs.merge(accept_language: "en-US,\u{1f600},he-IL")
      expect {
        hash = described_class.call(**inputs)
        expect(hash.length).to eq(64)
      }.not_to raise_error
    end

    it "edge: an all-empty input set still produces a 64-char digest" do
      hash = described_class.call
      expect(hash.length).to eq(64)
    end

    it "flaw: rejects a canvas_hash kwarg (LD-2 forbidden inputs)" do
      expect {
        described_class.call(**full_inputs, canvas_hash: "abc123")
      }.to raise_error(ArgumentError, /canvas_hash/)
    end

    it "flaw: rejects an audio_hash kwarg" do
      expect {
        described_class.call(**full_inputs, audio_hash: "x")
      }.to raise_error(ArgumentError, /audio_hash/)
    end

    it "flaw: rejects a webgl_renderer kwarg" do
      expect {
        described_class.call(**full_inputs, webgl_renderer: "x")
      }.to raise_error(ArgumentError, /webgl_renderer/)
    end

    it "flaw: rejects a font_list kwarg" do
      expect {
        described_class.call(**full_inputs, font_list: "x")
      }.to raise_error(ArgumentError, /font_list/)
    end

    it "composes from an ActionDispatch::Request when given" do
      request = ActionDispatch::TestRequest.create
      request.headers["User-Agent"] = "TestAgent/1.0"
      request.headers["Accept-Language"] = "en-US"

      h1 = described_class.call(request: request, screen_hint: "x", locale_hint: "y")
      h2 = described_class.call(
        user_agent: "TestAgent/1.0",
        accept_language: "en-US",
        accept: request.headers["Accept"],
        accept_encoding: request.headers["Accept-Encoding"],
        sec_ch_ua_platform: nil,
        sec_ch_ua_mobile: nil,
        screen_hint: "x",
        locale_hint: "y"
      )
      expect(h1).to eq(h2)
    end
  end
end
