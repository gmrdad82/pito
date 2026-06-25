# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Achievement::BadgeComponent do
  def render_badge(threshold:, metric:, unlocked_on: nil, form: :extended)
    render_inline(described_class.new(threshold: threshold, metric: metric,
                                      unlocked_on: unlocked_on, form: form))
  end

  # ── Single uniform bordered element (no per-metric box drawing) ──

  describe "uniform bordered badge" do
    it "renders exactly one .pito-achievement-badge element regardless of metric" do
      %i[subs subs_gained views watched_hours likes comments].each do |metric|
        node = render_badge(threshold: 100, metric: metric)
        expect(node.css(".pito-achievement-badge").length).to eq(1)
      end
    end

    it "renders no box-drawing glyphs (border is pure CSS now)" do
      node = render_badge(threshold: 1_000, metric: :subs, unlocked_on: Date.new(2026, 8, 1))
      text = node.css(".pito-achievement-badge").text
      box_drawing = /[╔╗╚╝═║╭╮╰╯─│┌┐└┘┈┊╌╎┏┓┗┛━┃]/
      expect(text).not_to match(box_drawing)
    end

    it "uses the same markup shape (no metric-specific border) across metrics" do
      # The badge element carries no metric-derived class/attribute — only the
      # shimmer offset + tier accent vary, never a per-metric border.
      faces = %i[subs views comments].map do |metric|
        node = render_badge(threshold: 100, metric: metric)
        node.css(".pito-achievement-badge").first.name
      end
      expect(faces.uniq).to eq([ "span" ])
    end
  end

  # ── Content: full-word labels (not single-letter abbreviations) ──────────

  describe "full-word labels" do
    {
      views:         "Views",
      likes:         "Likes",
      comments:      "Comments",
      watched_hours: "Watched",
      subs:          "Subs",
      subs_gained:   "Subs"
    }.each do |metric, word|
      it "renders '#{word}' (full word) for metric :#{metric}" do
        node = render_badge(threshold: 100, metric: metric)
        expect(node.css(".pito-achievement-badge").text).to include("100 #{word}")
      end
    end

    it "does not render single-letter abbreviations on the badge face" do
      %i[views likes comments watched_hours subs].each do |metric|
        node = render_badge(threshold: 100, metric: metric)
        text = node.css(".pito-achievement-badge").text
        # Single-letter abbrs (S/V/L/C/W) preceded by a space should not appear
        %w[V L C W].each do |abbr|
          expect(text).not_to match(/\b100 #{abbr}\b/)
        end
      end
    end

    it "formats the value via CompactCount" do
      {
           1_000 => "1K",
         500_000 => "500K",
      10_000_000 => "10M",
               5 => "5"
      }.each do |threshold, formatted|
        node = render_badge(threshold: threshold, metric: :subs)
        expect(node.css(".pito-achievement-badge").text).to include(formatted)
      end
    end
  end

  # ── Pluralisation by threshold (SB11 — the "1 Likes" bug) ──────────────────

  describe "singular badge face at threshold 1" do
    {
      subs:        "1 Sub",
      subs_gained: "1 Sub",
      views:       "1 View",
      likes:       "1 Like",
      comments:    "1 Comment"
    }.each do |metric, singular|
      it "renders '#{singular}' (singular) for :#{metric} at threshold 1" do
        text = render_badge(threshold: 1, metric: metric).css(".pito-achievement-badge").text
        expect(text).to include(singular)
        expect(text).not_to include("#{singular}s") # no "1 Likes"
      end
    end

    it "keeps 'Watched' invariant for watched_hours at threshold 1" do
      text = render_badge(threshold: 1, metric: :watched_hours).css(".pito-achievement-badge").text
      expect(text).to include("1 Watched")
    end

    it "uses the PLURAL face for thresholds above 1" do
      { 2 => "2 Likes", 100 => "100 Likes", 1_000 => "1K Subs" }.each do |threshold, expected|
        metric = expected.include?("Sub") ? :subs : :likes
        text   = render_badge(threshold: threshold, metric: metric).css(".pito-achievement-badge").text
        expect(text).to include(expected)
      end
    end
  end

  # ── Compact form ─────────────────────────────────────────────────────────

  describe "compact form (form: :compact)" do
    subject(:node) { render_badge(threshold: 1_000, metric: :subs, unlocked_on: Date.new(2026, 8, 1), form: :compact) }

    it "renders value + full word" do
      expect(node.css(".pito-achievement-badge").text).to include("1K Subs")
    end

    it "does not render a date span" do
      expect(node.css(".pito-achievement-badge__date")).to be_empty
    end

    it "does not include a middot-separated date" do
      expect(node.css(".pito-achievement-badge").text).not_to match(/·\s+[A-Z][a-z]{2}\s+'/)
    end

    it "omits the date even when unlocked_on is present" do
      node_with_date = render_badge(threshold: 100, metric: :views, unlocked_on: Date.new(2025, 1, 15), form: :compact)
      expect(node_with_date.css(".pito-achievement-badge__date")).to be_empty
    end

    it "renders value + full word for every metric" do
      {
        views:         "Views",
        likes:         "Likes",
        comments:      "Comments",
        watched_hours: "Watched",
        subs:          "Subs",
        subs_gained:   "Subs"
      }.each do |metric, word|
        n = render_badge(threshold: 100, metric: metric, form: :compact)
        expect(n.css(".pito-achievement-badge").text).to include("100 #{word}")
      end
    end
  end

  # ── Extended form ─────────────────────────────────────────────────────────

  describe "extended form (form: :extended, the default)" do
    context "with unlocked_on set" do
      subject(:node) { render_badge(threshold: 1_000, metric: :subs, unlocked_on: Date.new(2026, 8, 1)) }

      it "renders value + full word in the badge" do
        text = node.css(".pito-achievement-badge").text
        expect(text).to include("1K Subs")
      end

      it "renders the date in a muted .pito-achievement-badge__date block span" do
        span = node.css(".pito-achievement-badge__date")
        expect(span).not_to be_empty
        expect(span.text).to eq("Aug '26")
      end

      it "date span contains no middot separator (block layout provides separation)" do
        span = node.css(".pito-achievement-badge__date")
        expect(span.text).not_to include("·")
      end

      it "date span carries the block class (own line)" do
        span = node.css(".pito-achievement-badge__date").first
        expect(span["class"]).to include("block")
      end

      it "keeps the date span so CSS can mute it independently of the tier" do
        face = node.css(".pito-achievement-badge").first
        expect(face.css(".pito-achievement-badge__date").length).to eq(1)
        text_without_date = face.text.sub(face.css(".pito-achievement-badge__date").text, "").strip
        expect(text_without_date).to eq("1K Subs")
      end

      it "badge text includes both value+word and the date" do
        text = node.css(".pito-achievement-badge").text
        expect(text).to include("1K Subs")
        expect(text).to include("Aug '26")
        expect(text).not_to include("· Aug")
      end
    end

    context "with unlocked_on nil" do
      subject(:node) { render_badge(threshold: 1_000, metric: :subs) }

      it "omits the date span entirely" do
        expect(node.css(".pito-achievement-badge__date")).to be_empty
      end

      it "does not include a middot-separated date in the face" do
        expect(node.css(".pito-achievement-badge").text).not_to match(/·\s+[A-Z][a-z]{2}\s+'/)
      end

      it "still renders value + full word" do
        expect(node.css(".pito-achievement-badge").text).to include("1K Subs")
      end
    end

    it "is the default form (no form: kwarg needed)" do
      node = render_inline(described_class.new(threshold: 1_000, metric: :subs, unlocked_on: Date.new(2026, 1, 1)))
      expect(node.css(".pito-achievement-badge__date")).not_to be_empty
    end
  end

  # ── Tier colour via data-accent (per threshold) ─────────────────

  describe "data-accent tier mapping" do
    {
             1 => "muted",
            10 => "green",
           100 => "cyan",
         1_000 => "blue",
        10_000 => "purple",
       100_000 => "orange",
     1_000_000 => "yellow",
    10_000_000 => "pito"
    }.each do |threshold, accent|
      it "maps threshold #{threshold} to data-accent=#{accent}" do
        node = render_badge(threshold: threshold, metric: :subs)
        expect(node.css(".pito-achievement-badge[data-accent='#{accent}']")).not_to be_empty
      end
    end
  end

  # ── Perimeter-shimmer stagger offset ────────────────────────────

  describe "shimmer offset class" do
    it "applies a shared .pito-shimmer-dN stagger bucket to the badge" do
      node = render_badge(threshold: 1_000, metric: :subs)
      classes = node.css(".pito-achievement-badge").first["class"]
      expect(classes).to match(/\bpito-shimmer-d\d+\b/)
    end

    it "derives the bucket from a stable threshold+metric key" do
      expected = Pito::Shimmer.offset_class("1000subs")
      node = render_badge(threshold: 1_000, metric: :subs)
      expect(node.css(".pito-achievement-badge.#{expected}")).not_to be_empty
    end
  end

  # ── Per-tier contrast perimeter-shimmer hook (CSS contract) ─────
  #
  # The travelling perimeter highlight must be a per-tier CONTRASTING accent
  # (--pito-badge-shimmer), never plain white (--fg-default), so it reads on
  # light tiers. Asserted against the compiled stylesheet because the hook lives
  # in CSS keyed off the badge's data-accent (no inline style by design).

  describe "per-tier contrast shimmer (CSS)" do
    css = Rails.root.join("app/assets/tailwind/application.css").read

    # tier accent → expected contrasting highlight accent token.
    {
      "muted"  => "cyan",
      "green"  => "yellow",
      "cyan"   => "orange",
      "blue"   => "orange",
      "purple" => "yellow",
      "orange" => "cyan",
      "yellow" => "blue",
      "pito"   => "orange"
    }.each do |tier, contrast|
      it "maps the #{tier} tier to a contrasting --pito-badge-shimmer (--accent-#{contrast})" do
        rule = css[/\.pito-achievement-badge\[data-accent="#{tier}"\][^}]*\}/]
        expect(rule).to be_present
        expect(rule).to match(/--pito-badge-shimmer:\s*var\(--accent-#{contrast}\)/)
      end
    end

    it "never uses white (--fg-default) as a tier's perimeter highlight" do
      expect(css).not_to match(/--pito-badge-shimmer:\s*var\(--fg-default\)/)
    end

    it "drives the perimeter conic-gradient from --pito-badge-shimmer" do
      expect(css).to match(/conic-gradient\(.*?var\(--pito-badge-shimmer/m)
    end
  end
end
