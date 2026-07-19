# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Notifications::PlainMessage do
  describe ".call" do
    it "strips <strong>/<b> with no bold decoration by default" do
      expect(described_class.call("<strong>Hi</strong>")).to eq("Hi")
      expect(described_class.call("<b>Done</b>")).to eq("Done")
    end

    it "renders <li> items as plain lines, no bullet glyph" do
      html = "<ul><li>Alpha</li><li>Beta</li></ul>"
      expect(described_class.call(html)).to eq("Alpha\nBeta")
    end

    it "turns <br> and block-element boundaries into newlines" do
      expect(described_class.call("a<br>b")).to eq("a\nb")
      expect(described_class.call("<div>one</div><div>two</div>")).to eq("one\n\ntwo")
    end

    it "decodes HTML entities" do
      expect(described_class.call("Tom &amp; Jerry &lt;3")).to eq("Tom & Jerry <3")
    end

    it "strips the private_reminder dedup marker and the space it was appended after" do
      message = "Finish uploading 3 vids. <!-- pito:private_reminder:2026-07-19 -->"
      expect(described_class.call(message)).to eq("Finish uploading 3 vids.")
    end

    it "passes plain text through unchanged" do
      expect(described_class.call("Nothing fancy here")).to eq("Nothing fancy here")
    end

    it "honors explicit bold:/bullet: overrides, matching WebhookFormatter's decorated output" do
      html = "<strong>Imported</strong><ul><li>First</li></ul>"
      expect(described_class.call(html, bold: "**", bullet: "- ")).to eq("**Imported**\n- First")
    end

    it "does not raise on malformed / unclosed HTML" do
      malformed = "<strong>unclosed <li>item & <broken"
      expect { described_class.call(malformed) }.not_to raise_error
    end

    it "does not raise on a nil message" do
      expect(described_class.call(nil)).to eq("")
    end
  end
end
