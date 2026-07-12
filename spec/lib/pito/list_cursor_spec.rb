# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::ListCursor do
  describe ".encode / .decode roundtrip" do
    it "roundtrips an array of mixed primitive values" do
      values = [ 1, "2026-06-27T00:00:00.123456Z", 502 ]
      token  = described_class.encode(values)
      # JSON normalises everything to its literal form; ints stay ints.
      expect(described_class.decode(token)).to eq(values)
    end

    it "produces a URL-safe token (no +, /, or = padding)" do
      token = described_class.encode([ 1, "a/b+c", 9 ])
      expect(token).not_to match(%r{[+/=]})
    end

    it "wraps a non-array value into an array before encoding" do
      expect(described_class.decode(described_class.encode("solo"))).to eq([ "solo" ])
    end
  end

  describe ".decode of bad input" do
    it "returns nil for nil" do
      expect(described_class.decode(nil)).to be_nil
    end

    it "returns nil for a blank string" do
      expect(described_class.decode("")).to be_nil
      expect(described_class.decode("   ")).to be_nil
    end

    it "returns nil for garbage that is not valid base64/JSON" do
      expect(described_class.decode("@@@not-a-cursor@@@")).to be_nil
    end

    it "returns nil when the decoded JSON is not an array" do
      token = Base64.urlsafe_encode64('{"a":1}', padding: false)
      expect(described_class.decode(token)).to be_nil
    end
  end
end
