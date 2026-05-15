require "rails_helper"

RSpec.describe ChannelsHelper, type: :helper do
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

  # Unit A0 — the 14-day rate-limit gate helpers (`title_gate_open?`,
  # `handle_gate_open?`, `title_unlock_date`, `handle_unlock_date`) and
  # `channel_reminder_name` were removed. They served only the now-cut
  # channel edit form / diff-apply path. The channel is a read-only
  # mirror; the surviving helpers below are display-only.

  describe "#channel_display_url" do
    # Phase 24+ density pass — the /channels index URL column picks
    # the cleanest outbound URL form. Handle wins; UC-id is the
    # fallback; raw `channel_url` is the last resort.
    it "returns the /@handle URL when the channel has a handle" do
      channel.handle = "@mshpoise"
      expect(helper.channel_display_url(channel))
        .to eq("https://www.youtube.com/@mshpoise")
    end

    it "returns the UC-id URL when the channel has no handle" do
      channel.handle = nil
      channel.channel_url = "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ"
      expect(helper.channel_display_url(channel))
        .to eq("https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ")
    end

    it "returns the UC-id URL when handle is the empty string" do
      channel.handle = ""
      channel.channel_url = "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ"
      expect(helper.channel_display_url(channel))
        .to eq("https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ")
    end

    it "returns the UC-id URL when handle is whitespace only" do
      channel.handle = "   "
      channel.channel_url = "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ"
      expect(helper.channel_display_url(channel))
        .to eq("https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ")
    end

    it "prefers the @handle URL even when the channel_url is also valid" do
      channel.handle = "@pitomd"
      channel.channel_url = "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ"
      expect(helper.channel_display_url(channel))
        .to eq("https://www.youtube.com/@pitomd")
    end

    it "falls back to the raw channel_url when the UC-id cannot be extracted" do
      # Defense in depth — the model regex prevents this on insert,
      # but the view never 500s if `channel_url` somehow drifts.
      channel.handle = nil
      channel.channel_url = "https://example.com/oops"
      expect(helper.channel_display_url(channel))
        .to eq("https://example.com/oops")
    end

    it "returns nil for a nil channel" do
      expect(helper.channel_display_url(nil)).to be_nil
    end
  end

  describe "#channel_url_label" do
    # 2026-05-11 — picker URL column visible-text helper. Handle wins
    # (rendered bare); UC-id is the middle-truncated fallback; raw
    # `channel_url` is the last resort.
    it "returns the bare @handle when the channel has a handle" do
      channel.handle = "@mshpoise"
      expect(helper.channel_url_label(channel)).to eq("@mshpoise")
    end

    it "returns the middle-truncated UC-id when the channel has no handle" do
      channel.handle = nil
      channel.channel_url = "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ"
      # head=6, tail=3 → "UC2T-W" + "…" + "uQQ"
      expect(helper.channel_url_label(channel)).to eq("UC2T-W…uQQ")
    end

    it "returns the truncated UC-id when handle is the empty string" do
      channel.handle = ""
      channel.channel_url = "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ"
      expect(helper.channel_url_label(channel)).to eq("UC2T-W…uQQ")
    end

    it "returns the truncated UC-id when handle is whitespace only" do
      channel.handle = "   "
      channel.channel_url = "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ"
      expect(helper.channel_url_label(channel)).to eq("UC2T-W…uQQ")
    end

    it "prefers the @handle even when the channel_url is also valid" do
      channel.handle = "@pitomd"
      channel.channel_url = "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ"
      expect(helper.channel_url_label(channel)).to eq("@pitomd")
    end

    it "falls back to the raw channel_url when the UC-id cannot be extracted" do
      channel.handle = nil
      channel.channel_url = "https://example.com/oops"
      expect(helper.channel_url_label(channel)).to eq("https://example.com/oops")
    end

    it "returns nil for a nil channel" do
      expect(helper.channel_url_label(nil)).to be_nil
    end
  end
end
