require "rails_helper"

RSpec.describe NotificationFormatter do
  describe ".severity_color" do
    it "returns 5_793_266 for :info" do
      expect(described_class.severity_color(:info)).to eq(5_793_266)
    end

    it "returns 5_763_719 for :success" do
      expect(described_class.severity_color(:success)).to eq(5_763_719)
    end

    it "returns 16_705_372 for :warn" do
      expect(described_class.severity_color(:warn)).to eq(16_705_372)
    end

    it "returns 15_548_997 for :urgent" do
      expect(described_class.severity_color(:urgent)).to eq(15_548_997)
    end

    it "accepts string severities" do
      expect(described_class.severity_color("info")).to eq(5_793_266)
    end

    it "raises ArgumentError on unknown severity" do
      expect { described_class.severity_color(:nope) }
        .to raise_error(ArgumentError, /unknown severity/)
    end
  end

  describe ".emoji_for" do
    {
      "video_published"                => "📺",
      "game_release_today"             => "🎮",
      "milestone_reached"              => "🏆",
      "calendar_entry_firing"          => "📅",
      "sync_error"                     => "🚨",
      "youtube_reauth_needed"          => "🔐"
    }.each do |event_type, glyph|
      it "returns #{glyph.inspect} for #{event_type.inspect}" do
        expect(described_class.emoji_for(event_type)).to eq(glyph)
      end
    end

    it "returns the stable fallback for unknown event types" do
      expect(described_class.emoji_for("unknown")).to eq("•")
    end
  end

  describe ".link" do
    it "returns markdown link form for :discord" do
      expect(described_class.link("watch", "https://example.com", channel: :discord))
        .to eq("[watch](https://example.com)")
    end

    it "returns slack <url|text> form for :slack" do
      expect(described_class.link("watch", "https://example.com", channel: :slack))
        .to eq("<https://example.com|watch>")
    end

    it "returns markdown link form for :in_app" do
      # In-app's consumer is ERB; the in_app formatter's markdown → HTML
      # stage handles conversion. The helper itself returns markdown.
      expect(described_class.link("watch", "https://example.com", channel: :in_app))
        .to eq("[watch](https://example.com)")
    end

    it "raises for unknown channel" do
      expect { described_class.link("x", "y", channel: :smtp) }
        .to raise_error(ArgumentError, /unknown channel/)
    end
  end

  describe ".escape_for" do
    it "backslash-escapes asterisks for :discord" do
      expect(described_class.escape_for("a *b* c", channel: :discord))
        .to eq("a \\*b\\* c")
    end

    it "escapes underscores for :discord" do
      expect(described_class.escape_for("a _b_ c", channel: :discord))
        .to eq("a \\_b\\_ c")
    end

    it "escapes brackets and parens for :discord" do
      expect(described_class.escape_for("a [b](c)", channel: :discord))
        .to eq("a \\[b\\]\\(c\\)")
    end

    it "escapes the backtick for :discord" do
      expect(described_class.escape_for("`code`", channel: :discord))
        .to eq("\\`code\\`")
    end

    it "escapes the angle brackets for :discord" do
      expect(described_class.escape_for("a > b", channel: :discord))
        .to eq("a \\> b")
    end

    it "html-encodes &, <, > for :slack" do
      expect(described_class.escape_for("a < b & c", channel: :slack))
        .to eq("a &lt; b &amp; c")
    end

    it "html-encodes > for :slack" do
      expect(described_class.escape_for("a > b", channel: :slack))
        .to eq("a &gt; b")
    end

    it "passes text through verbatim for :in_app" do
      expect(described_class.escape_for("a *b* <c>", channel: :in_app))
        .to eq("a *b* <c>")
    end

    it "returns empty string for nil" do
      expect(described_class.escape_for(nil, channel: :discord)).to eq("")
    end

    it "raises for unknown channel" do
      expect { described_class.escape_for("x", channel: :smtp) }
        .to raise_error(ArgumentError, /unknown channel/)
    end
  end

  describe ".truncate_for" do
    it "appends a Unicode ellipsis when truncating" do
      result = described_class.truncate_for("hello world", limit: 5)
      expect(result).to eq("hell…")
    end

    it "does NOT use three ASCII dots" do
      result = described_class.truncate_for("hello world", limit: 5)
      expect(result).not_to end_with("...")
      expect(result.last).to eq("…")
    end

    it "passes through strings shorter than the limit" do
      expect(described_class.truncate_for("hello", limit: 100)).to eq("hello")
    end

    it "passes through strings exactly at the limit" do
      expect(described_class.truncate_for("hello", limit: 5)).to eq("hello")
    end

    it "rolls back to before a half-open `[` when the link would split" do
      result = described_class.truncate_for("[click here](https://example.com)", limit: 5)
      # Must not leave a half-open `[`. The roll-back drops the `[`
      # entirely; what remains is just the ellipsis (or empty + ellipsis).
      expect(result.count("[")).to eq(result.count("]"))
    end

    it "produces exactly N characters when long input is cut to N" do
      input = "a" * 5000
      result = described_class.truncate_for(input, limit: 4096)
      expect(result.length).to eq(4096)
      expect(result).to end_with("…")
    end

    it "returns empty string for nil" do
      expect(described_class.truncate_for(nil, limit: 5)).to eq("")
    end

    it "returns just the ellipsis when limit is tiny" do
      expect(described_class.truncate_for("hello", limit: 1)).to eq("…")
    end
  end

  describe ".format_timestamp" do
    let(:time) { Time.utc(2026, 5, 10, 12, 0, 0) }

    it "formats :iso as ISO-8601 UTC with Z suffix" do
      expect(described_class.format_timestamp(time, :iso))
        .to eq("2026-05-10T12:00:00Z")
    end

    it "formats :relative via time_ago_in_words" do
      result = described_class.format_timestamp(5.minutes.ago, :relative)
      expect(result).to match(/minutes? ago/)
    end

    it "returns nil for nil input" do
      expect(described_class.format_timestamp(nil, :iso)).to be_nil
    end

    it "raises for unknown format" do
      expect { described_class.format_timestamp(time, :rfc822) }
        .to raise_error(ArgumentError)
    end
  end

  describe ".absolute_url" do
    before do
      allow(Rails.application.routes).to receive(:default_url_options)
        .and_return(host: "app.pitomd.com", protocol: "https")
    end

    it "prepends the install host to leading-slash paths" do
      expect(described_class.absolute_url("/notifications/42"))
        .to eq("https://app.pitomd.com/notifications/42")
    end

    it "passes through absolute http(s) URLs verbatim" do
      expect(described_class.absolute_url("https://example.com/x"))
        .to eq("https://example.com/x")
    end

    it "returns nil for nil" do
      expect(described_class.absolute_url(nil)).to be_nil
    end

    it "returns nil for blank string" do
      expect(described_class.absolute_url("")).to be_nil
    end

    it "falls back to https://app.pitomd.com when host config is missing" do
      allow(Rails.application.routes).to receive(:default_url_options).and_return({})
      expect(described_class.absolute_url("/x")).to eq("https://app.pitomd.com/x")
    end
  end

  describe ".avatar_url" do
    it "reads from credentials.notifications.pito_avatar_url" do
      allow(Rails.application.credentials).to receive(:dig).and_return(nil)
      allow(Rails.application.credentials)
        .to receive(:dig).with(:notifications, :pito_avatar_url)
        .and_return("https://example.com/pito.png")
      expect(described_class.avatar_url).to eq("https://example.com/pito.png")
    end

    it "returns nil when not configured" do
      allow(Rails.application.credentials).to receive(:dig).and_return(nil)
      expect(described_class.avatar_url).to be_nil
    end
  end

  describe ".template_for" do
    it "resolves the right class via the registry" do
      n = build_stubbed(:notification, :video_published, with_calendar_entry: false, dedup_key: "tpl-vp")
      expect(described_class.template_for(n))
        .to be_a(NotificationFormatter::Templates::VideoPublished)
    end

    it "raises a clear ArgumentError for an unknown event_type" do
      n = build(:notification, event_type: "definitely_not_a_real_event")
      n.save!(validate: false)
      expect { described_class.template_for(n) }
        .to raise_error(ArgumentError, /no template registered/)
    end
  end
end
