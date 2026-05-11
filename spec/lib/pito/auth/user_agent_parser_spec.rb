require "rails_helper"

RSpec.describe Pito::Auth::UserAgentParser do
  describe ".call" do
    it "happy: Chrome on macOS" do
      ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
           "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
      out = described_class.call(ua)
      expect(out[:browser]).to eq("Chrome")
      expect(out[:os]).to eq("macOS")
    end

    it "happy: Firefox on Linux" do
      ua = "Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0"
      out = described_class.call(ua)
      expect(out[:browser]).to eq("Firefox")
      expect(out[:os]).to eq("Linux")
    end

    it "happy: Safari on iOS reports iOS" do
      ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 " \
           "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
      out = described_class.call(ua)
      expect(out[:os]).to eq("iOS")
    end

    it "sad: empty UA → Unknown/Unknown" do
      expect(described_class.call("")).to eq(browser: "Unknown", os: "Unknown")
    end

    it "sad: nil UA → Unknown/Unknown" do
      expect(described_class.call(nil)).to eq(browser: "Unknown", os: "Unknown")
    end

    it "edge: curl bot UA is named (browser identifier preserved)" do
      out = described_class.call("curl/8.5.0")
      expect(out[:browser]).to eq("curl")
    end

    it "never raises, even on malformed inputs" do
      expect { described_class.call("\xff\xff\xff") }.not_to raise_error
    end
  end
end
