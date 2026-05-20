require "rails_helper"

# Beta 4 — Phase F2. RSpec coverage for `Tui::IndicatorComponent`.
# Locks the 2 variants × 4 modes matrix, the `start_offset:` stagger
# math, the progress bar grammar (`[▓▓▓░░░] N/M`), and the
# ArgumentError contract on unknown variant / mode.
#
# This is the presentational primitive; Stimulus animation is locked
# separately in `spec/javascript/tui_indicator_controller_spec.rb`.
RSpec.describe Tui::IndicatorComponent, type: :component do
  describe "constants" do
    it "exposes the locked set of 2 variants" do
      expect(described_class::VARIANTS).to match_array(%i[bounce_equals braille])
    end

    it "exposes the locked set of 4 modes" do
      expect(described_class::MODES).to match_array(%i[idle indeterminate progress error])
    end

    it "locks the 6-frame bounce_equals sequence" do
      expect(described_class::BOUNCE_EQUALS_FRAMES).to eq(
        [ "=---", "-=--", "--=-", "---=", "--=-", "-=--" ]
      )
    end

    it "locks the 10-frame braille sequence" do
      expect(described_class::BRAILLE_FRAMES).to eq(
        [ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" ]
      )
    end

    it "locks the progress bar width at 8" do
      expect(described_class::PROGRESS_BAR_WIDTH).to eq(8)
    end
  end

  describe "argument validation" do
    it "raises ArgumentError on unknown variant" do
      expect {
        described_class.new(variant: :nope)
      }.to raise_error(ArgumentError, /unknown variant nope/)
    end

    it "raises ArgumentError on unknown mode" do
      expect {
        described_class.new(variant: :braille, mode: :nope)
      }.to raise_error(ArgumentError, /unknown mode nope/)
    end

    it "coerces string variant via to_sym" do
      component = described_class.new(variant: "braille", mode: :idle)
      expect(component.variant).to eq(:braille)
    end

    it "coerces string mode via to_sym" do
      component = described_class.new(variant: :braille, mode: "idle")
      expect(component.mode).to eq(:idle)
    end
  end

  describe "frames helper" do
    it "returns the bounce_equals frames for :bounce_equals" do
      component = described_class.new(variant: :bounce_equals, mode: :idle)
      expect(component.frames).to eq(described_class::BOUNCE_EQUALS_FRAMES)
    end

    it "returns the braille frames for :braille" do
      component = described_class.new(variant: :braille, mode: :idle)
      expect(component.frames).to eq(described_class::BRAILLE_FRAMES)
    end
  end

  describe "css_class helper" do
    it "composes base + variant + mode classes" do
      component = described_class.new(variant: :braille, mode: :progress)
      expect(component.css_class).to eq("tui-indicator tui-indicator--braille tui-indicator--progress")
    end
  end

  describe "initial_frame (idle / indeterminate SSR seed)" do
    it "returns frames[0] when start_offset is 0" do
      component = described_class.new(variant: :bounce_equals, mode: :indeterminate, start_offset: 0)
      expect(component.initial_frame).to eq("=---")
    end

    it "honors start_offset modulo frame count for bounce_equals (6 frames)" do
      component = described_class.new(variant: :bounce_equals, mode: :indeterminate, start_offset: 2)
      expect(component.initial_frame).to eq("--=-")
    end

    it "wraps start_offset past the end via modulo" do
      # 7 % 6 == 1
      component = described_class.new(variant: :bounce_equals, mode: :indeterminate, start_offset: 7)
      expect(component.initial_frame).to eq("-=--")
    end

    it "honors start_offset modulo frame count for braille (10 frames)" do
      component = described_class.new(variant: :braille, mode: :indeterminate, start_offset: 3)
      expect(component.initial_frame).to eq("⠸")
    end

    it "coerces non-integer start_offset via to_i" do
      component = described_class.new(variant: :braille, mode: :indeterminate, start_offset: "4")
      expect(component.start_offset).to eq(4)
      expect(component.initial_frame).to eq("⠼")
    end
  end

  describe "progress mode — bar + counter" do
    it "renders an 8-char bar with the correct fill ratio" do
      component = described_class.new(
        variant: :bounce_equals, mode: :progress,
        progress_current: 3, progress_total: 8
      )
      expect(component.progress_bar).to eq("[▓▓▓░░░░░]")
    end

    it "rounds the fill ratio (5/8 -> 5 filled)" do
      component = described_class.new(
        variant: :bounce_equals, mode: :progress,
        progress_current: 5, progress_total: 8
      )
      expect(component.progress_bar).to eq("[▓▓▓▓▓░░░]")
    end

    it "clamps fill to the bar width (current > total -> all filled)" do
      component = described_class.new(
        variant: :bounce_equals, mode: :progress,
        progress_current: 99, progress_total: 8
      )
      expect(component.progress_bar).to eq("[▓▓▓▓▓▓▓▓]")
    end

    it "renders 0 filled when current is 0" do
      component = described_class.new(
        variant: :bounce_equals, mode: :progress,
        progress_current: 0, progress_total: 8
      )
      expect(component.progress_bar).to eq("[░░░░░░░░]")
    end

    it "returns nil for progress_bar when total is 0 (avoids div-by-zero)" do
      component = described_class.new(
        variant: :bounce_equals, mode: :progress,
        progress_current: 0, progress_total: 0
      )
      expect(component.progress_bar).to be_nil
    end

    it "returns nil for progress_bar when mode is not :progress" do
      component = described_class.new(
        variant: :bounce_equals, mode: :idle,
        progress_current: 3, progress_total: 8
      )
      expect(component.progress_bar).to be_nil
    end

    it "renders the counter as `current/total`" do
      component = described_class.new(
        variant: :bounce_equals, mode: :progress,
        progress_current: 3, progress_total: 8
      )
      expect(component.progress_label).to eq("3/8")
    end

    it "returns nil for progress_label when mode is not :progress" do
      component = described_class.new(variant: :bounce_equals, mode: :idle)
      expect(component.progress_label).to be_nil
    end

    it "returns nil for progress_label when either value is nil" do
      component = described_class.new(
        variant: :bounce_equals, mode: :progress,
        progress_current: nil, progress_total: 8
      )
      expect(component.progress_label).to be_nil
    end
  end

  describe "rendering — 2 variants × 4 modes" do
    %i[bounce_equals braille].each do |variant|
      context "variant: #{variant.inspect}" do
        it "renders :idle with the variant + mode classes and no initial text content" do
          render_inline(described_class.new(variant: variant, mode: :idle))

          expect(page).to have_css("span.tui-indicator.tui-indicator--#{variant}.tui-indicator--idle")
        end

        it "renders :indeterminate seeded with the initial frame and Stimulus wiring" do
          render_inline(described_class.new(variant: variant, mode: :indeterminate, start_offset: 0))

          expect(page).to have_css(
            "span.tui-indicator.tui-indicator--#{variant}.tui-indicator--indeterminate" \
            "[data-controller='tui-indicator']" \
            "[data-tui-indicator-variant-value='#{variant}']" \
            "[data-tui-indicator-start-offset-value='0']"
          )
        end

        it "renders :indeterminate with the initial frame as text content" do
          component = described_class.new(variant: variant, mode: :indeterminate, start_offset: 0)
          render_inline(component)

          expect(page).to have_css(".tui-indicator--indeterminate", text: component.initial_frame)
        end

        it "renders :progress with bar + counter and no Stimulus wiring" do
          render_inline(described_class.new(
            variant: variant, mode: :progress,
            progress_current: 2, progress_total: 8
          ))

          expect(page).to have_css("span.tui-indicator.tui-indicator--#{variant}.tui-indicator--progress")
          expect(page).to have_css(".tui-indicator__bar", text: "[▓▓░░░░░░]")
          expect(page).to have_css(".tui-indicator__counter", text: "2/8")
          expect(page).not_to have_css("[data-controller='tui-indicator']")
        end

        it "renders :error as a static ✗ with no Stimulus wiring" do
          render_inline(described_class.new(variant: variant, mode: :error))

          expect(page).to have_css("span.tui-indicator.tui-indicator--#{variant}.tui-indicator--error", text: "✗")
          expect(page).not_to have_css("[data-controller='tui-indicator']")
        end
      end
    end
  end

  describe ":idle Stimulus wiring (renders the controller for future state flips)" do
    it "attaches data-controller='tui-indicator' on :idle so the controller can hydrate" do
      render_inline(described_class.new(variant: :braille, mode: :idle, start_offset: 4))

      expect(page).to have_css(
        "span.tui-indicator--idle" \
        "[data-controller='tui-indicator']" \
        "[data-tui-indicator-variant-value='braille']" \
        "[data-tui-indicator-start-offset-value='4']"
      )
    end
  end

  describe "stagger via start_offset" do
    it "two :indeterminate instances with different offsets render different initial frames" do
      a = described_class.new(variant: :braille, mode: :indeterminate, start_offset: 0)
      b = described_class.new(variant: :braille, mode: :indeterminate, start_offset: 5)

      expect(a.initial_frame).to eq("⠋")
      expect(b.initial_frame).to eq("⠴")
    end
  end
end
