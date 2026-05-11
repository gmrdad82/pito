require "rails_helper"

RSpec.describe ChannelsHelper, type: :helper do
  include ActiveSupport::Testing::TimeHelpers

  let(:channel) { build_stubbed(:channel) }

  describe "#formatted_subscriber_count" do
    it "returns 'Hidden' when hidden_subscriber_count? is true" do
      channel.hidden_subscriber_count = true
      channel.subscriber_count = 12_345
      expect(helper.formatted_subscriber_count(channel)).to eq("Hidden")
    end

    it "returns the delimited count when subscriber_count is set and not hidden" do
      channel.hidden_subscriber_count = false
      channel.subscriber_count = 12_345
      expect(helper.formatted_subscriber_count(channel)).to eq("12,345")
    end

    it "returns the em dash when subscriber_count is nil and not hidden" do
      channel.hidden_subscriber_count = false
      channel.subscriber_count = nil
      expect(helper.formatted_subscriber_count(channel)).to eq("—")
    end

    it "returns 'Hidden' even when subscriber_count is nil" do
      # The 'hidden' state wins regardless of whether YouTube returned
      # a numeric value alongside the flag.
      channel.hidden_subscriber_count = true
      channel.subscriber_count = nil
      expect(helper.formatted_subscriber_count(channel)).to eq("Hidden")
    end

    it "returns '0' for a zero subscriber count" do
      channel.hidden_subscriber_count = false
      channel.subscriber_count = 0
      expect(helper.formatted_subscriber_count(channel)).to eq("0")
    end
  end

  describe "#formatted_view_count" do
    it "returns the delimited count when present" do
      channel.view_count = 1_000_000
      expect(helper.formatted_view_count(channel)).to eq("1,000,000")
    end

    it "returns the em dash when nil" do
      channel.view_count = nil
      expect(helper.formatted_view_count(channel)).to eq("—")
    end

    it "returns '0' for a zero view count" do
      channel.view_count = 0
      expect(helper.formatted_view_count(channel)).to eq("0")
    end
  end

  describe "#formatted_video_count" do
    it "returns the delimited count when present" do
      channel.video_count = 1_234
      expect(helper.formatted_video_count(channel)).to eq("1,234")
    end

    it "returns the em dash when nil" do
      channel.video_count = nil
      expect(helper.formatted_video_count(channel)).to eq("—")
    end

    it "returns '0' for a zero video count" do
      channel.video_count = 0
      expect(helper.formatted_video_count(channel)).to eq("0")
    end
  end

  describe "#channel_display_title" do
    it "returns the title when set" do
      channel.title = "Pito Test Channel"
      expect(helper.channel_display_title(channel)).to eq("Pito Test Channel")
    end

    it "returns the placeholder when title is nil" do
      channel.title = nil
      expect(helper.channel_display_title(channel)).to eq("untitled channel")
    end

    it "returns the placeholder when title is the empty string" do
      channel.title = ""
      expect(helper.channel_display_title(channel)).to eq("untitled channel")
    end

    it "returns the placeholder when title is whitespace only" do
      channel.title = "   "
      expect(helper.channel_display_title(channel)).to eq("untitled channel")
    end
  end

  describe "#channel_description_html" do
    it "returns nil when description is nil" do
      channel.description = nil
      expect(helper.channel_description_html(channel)).to be_nil
    end

    it "returns nil when description is the empty string" do
      channel.description = ""
      expect(helper.channel_description_html(channel)).to be_nil
    end

    it "returns nil when description is whitespace only" do
      channel.description = "   \n  "
      expect(helper.channel_description_html(channel)).to be_nil
    end

    it "wraps plain text in a <p> tag" do
      channel.description = "A devlog about building Pito."
      result = helper.channel_description_html(channel)
      expect(result).to include("<p>")
      expect(result).to include("A devlog about building Pito.")
    end

    it "preserves line breaks via <br>" do
      channel.description = "line one\nline two"
      result = helper.channel_description_html(channel)
      expect(result).to include("line one")
      expect(result).to include("<br")
      expect(result).to include("line two")
    end

    it "auto-links bare https URLs" do
      channel.description = "see https://example.com for details"
      result = helper.channel_description_html(channel)
      expect(result).to match(/<a [^>]*href="https:\/\/example\.com"/)
      expect(result).to include('target="_blank"')
      expect(result).to include('rel="noopener noreferrer"')
    end

    it "auto-links bare http URLs" do
      channel.description = "old http://example.com"
      result = helper.channel_description_html(channel)
      expect(result).to match(/<a [^>]*href="http:\/\/example\.com"/)
    end

    it "auto-links multiple URLs in the same description" do
      channel.description = "a https://a.example b https://b.example"
      result = helper.channel_description_html(channel)
      expect(result).to match(/<a [^>]*href="https:\/\/a\.example"/)
      expect(result).to match(/<a [^>]*href="https:\/\/b\.example"/)
    end

    it "strips <script> tags via simple_format's sanitize pipeline" do
      # Rails' html-sanitizer strips the executable tag itself but keeps
      # the literal inner text. The XSS guarantee is that no real
      # `<script>` tag survives — the JS body becomes inert text.
      channel.description = "<script>alert('xss')</script>safe text"
      result = helper.channel_description_html(channel)
      expect(result).not_to include("<script>")
      expect(result).not_to include("</script>")
      expect(result).to include("safe text")
    end

    it "strips inline event handlers" do
      channel.description = "<img onerror=alert(1) src=x>safe"
      result = helper.channel_description_html(channel)
      expect(result).not_to match(/onerror/)
      expect(result).to include("safe")
    end

    it "returns html_safe output" do
      channel.description = "plain text"
      result = helper.channel_description_html(channel)
      expect(result).to be_html_safe
    end
  end

  # Phase 7.5 §11c — 14-day rate-limit gate helpers.
  #
  # The gate is **open** while `*_changed_at` is strictly inside the
  # 14-day window. Exactly 14 days ago is treated as **closed** — the
  # window has just expired and the field can be re-edited.
  describe "#title_gate_open?" do
    it "is false when title_changed_at is nil (field has never been edited)" do
      channel.title_changed_at = nil
      expect(helper.title_gate_open?(channel)).to be(false)
    end

    it "is true when title_changed_at is within the 14-day window" do
      channel.title_changed_at = 3.days.ago
      expect(helper.title_gate_open?(channel)).to be(true)
    end

    it "is false when title_changed_at is older than 14 days" do
      channel.title_changed_at = 15.days.ago
      expect(helper.title_gate_open?(channel)).to be(false)
    end

    it "is false at the exact 14-day boundary (window just expired)" do
      travel_to(Time.current) do
        channel.title_changed_at = 14.days.ago
        expect(helper.title_gate_open?(channel)).to be(false)
      end
    end

    it "is true at 13 days + 23 hours (still strictly inside the window)" do
      channel.title_changed_at = (14.days - 1.hour).ago
      expect(helper.title_gate_open?(channel)).to be(true)
    end
  end

  describe "#handle_gate_open?" do
    it "is false when handle_changed_at is nil" do
      channel.handle_changed_at = nil
      expect(helper.handle_gate_open?(channel)).to be(false)
    end

    it "is true when handle_changed_at is within the 14-day window" do
      channel.handle_changed_at = 1.day.ago
      expect(helper.handle_gate_open?(channel)).to be(true)
    end

    it "is false when handle_changed_at is older than 14 days" do
      channel.handle_changed_at = 30.days.ago
      expect(helper.handle_gate_open?(channel)).to be(false)
    end

    it "is false at the exact 14-day boundary" do
      travel_to(Time.current) do
        channel.handle_changed_at = 14.days.ago
        expect(helper.handle_gate_open?(channel)).to be(false)
      end
    end
  end

  describe "#title_unlock_date" do
    it "returns nil when title_changed_at is nil" do
      channel.title_changed_at = nil
      expect(helper.title_unlock_date(channel)).to be_nil
    end

    it "returns the YYYY-MM-DD string for `title_changed_at + 14.days`" do
      changed = Time.zone.parse("2026-05-01 12:00:00")
      channel.title_changed_at = changed
      expect(helper.title_unlock_date(channel)).to eq("2026-05-15")
    end

    it "ignores time-of-day when formatting (date only)" do
      channel.title_changed_at = Time.zone.parse("2026-05-01 23:59:59")
      expect(helper.title_unlock_date(channel)).to eq("2026-05-15")
    end
  end

  describe "#handle_unlock_date" do
    it "returns nil when handle_changed_at is nil" do
      channel.handle_changed_at = nil
      expect(helper.handle_unlock_date(channel)).to be_nil
    end

    it "returns the YYYY-MM-DD string for `handle_changed_at + 14.days`" do
      changed = Time.zone.parse("2026-05-01 12:00:00")
      channel.handle_changed_at = changed
      expect(helper.handle_unlock_date(channel)).to eq("2026-05-15")
    end
  end
end
