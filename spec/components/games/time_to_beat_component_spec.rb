require "rails_helper"

# Wave F consolidation — spec coverage for `Games::TimeToBeatComponent`.
#
# The component is the canonical TTB visualization: a horizontal fuel
# gauge with 3 colored pillar ticks (main / extras / completionist) +
# 1 footage notch, an adaptive cool-spectrum gradient (green → lime →
# amber → pink) projected onto FIXED hour thresholds (10 / 40 / 100),
# and pillar bottom labels with pull-apart collision handling.
#
# Coverage matches the surface listed in the dispatch brief:
#   - SAMPLE_HOURS fallback (no IGDB data)
#   - HEAT_THRESHOLDS projection onto `max_x`
#   - `pillar_label_data` tick positions
#   - BOTTOM_LABEL_COLLISION_THRESHOLD_PCT + NUDGE_PCT pull-apart math
#   - I18n label resolution
#   - `footage_label_alignment_class` (0h → at-start, >0h → centered)
#   - Adaptive gradient stops at fixed HOUR thresholds (not bar %)
RSpec.describe Games::TimeToBeatComponent, type: :component do
  # ------------------------------------------------------------------
  # #render — happy path covering ticks, gradient, footage alignment.
  # ------------------------------------------------------------------

  describe "#render" do
    # max_x = max(200, 50, 10) * 1.05 = 210
    #   main  = 50/210  = 23.81 %
    #   extras= 100/210 = 47.619 %
    #   compl = 200/210 = 95.238 %
    let(:game) { build_stubbed(:game, :synced) }

    before do
      render_inline(described_class.new(game: game, footage_hours: 50))
    end

    it "wraps the markup with the fuel-gauge class + data attributes" do
      expect(page).to have_css('div.ttb-fuel-gauge[data-component="time-to-beat"][data-variant="fuel_gauge"]')
    end

    it "renders the main pillar tick at the expected % position" do
      tick = page.find('div.ttb-fuel-gauge__tick--main')
      expect(tick["style"]).to include("left: 23.81%")
    end

    it "renders the extras pillar tick at the expected % position" do
      tick = page.find('div.ttb-fuel-gauge__tick--extras')
      expect(tick["style"]).to include("left: 47.619%")
    end

    it "renders the completionist pillar tick at the expected % position" do
      tick = page.find('div.ttb-fuel-gauge__tick--completionist')
      expect(tick["style"]).to include("left: 95.238%")
    end

    it "renders the footage tick at the expected % position" do
      tick = page.find('div.ttb-fuel-gauge__tick--footage')
      expect(tick["style"]).to include("left: 23.81%")
      expect(tick["data-footage-hours"]).to eq("50")
    end

    it "inlines the cool-spectrum gradient as background-image" do
      bar = page.find('div.ttb-fuel-gauge__bar-layer--real')
      expect(bar["style"]).to include("background-image: linear-gradient(to right,")
      # green / lime / amber / pink — color literals from HEAT_THRESHOLDS.
      expect(bar["style"]).to include("#4CAF50")
      expect(bar["style"]).to include("#CDDC39")
      expect(bar["style"]).to include("#FFB74D")
      expect(bar["style"]).to include("#E91E63")
    end

    it "right-side-anchors the gradient with a trailing 100 % stop" do
      bar = page.find('div.ttb-fuel-gauge__bar-layer--real')
      # The last HEAT_THRESHOLDS stop is `#E91E63` (pink). With max_x = 210
      # the 100h threshold lands at ~47.62 %, so a trailing `pink 100%`
      # extension stop is appended.
      expect(bar["style"]).to include("#E91E63 100%")
    end

    it "centers the footage value label (footage_hours > 0)" do
      label = page.find('span.ttb-fuel-gauge__value--footage')
      expect(label[:class]).to include("ttb-fuel-gauge__label--centered")
      expect(label[:class]).not_to include("ttb-fuel-gauge__label--at-start")
    end

    it "labels the footage value with the i18n-resolved hours_short string" do
      expect(page.find('span.ttb-fuel-gauge__value--footage').text.strip).to eq("50h")
    end

    it "renders all four legend swatches (3 pillars + footage)" do
      expect(page).to have_css('span.ttb-fuel-gauge__legend-swatch--main')
      expect(page).to have_css('span.ttb-fuel-gauge__legend-swatch--extras')
      expect(page).to have_css('span.ttb-fuel-gauge__legend-swatch--completionist')
      expect(page).to have_css('span.ttb-fuel-gauge__legend-swatch--footage')
    end

    it "exposes the inline TTB watermark inside the bar" do
      expect(page).to have_css('span.ttb-fuel-gauge__title', text: "TTB")
    end
  end

  # ------------------------------------------------------------------
  # SAMPLE_HOURS fallback — exposed via `#hours` instance method when
  # the game has no IGDB ttb data. SAMPLE_HOURS is `{31, 71, 124}` per
  # the component's reference screenshot.
  # ------------------------------------------------------------------

  describe "SAMPLE_HOURS fallback (`#hours`)" do
    it "is the documented sample triplet {main: 31, extras: 71, completionist: 124}" do
      expect(described_class::SAMPLE_HOURS).to eq(main: 31, extras: 71, completionist: 124)
    end

    it "falls back to SAMPLE_HOURS when the game has no IGDB ttb seconds" do
      bare = build_stubbed(:game,
                           ttb_main_seconds: 0,
                           ttb_extras_seconds: 0,
                           ttb_completionist_seconds: 0)
      component = described_class.new(game: bare)

      expect(component.hours).to eq(described_class::SAMPLE_HOURS)
    end

    it "falls back to SAMPLE_HOURS when ttb seconds are all nil" do
      bare = build_stubbed(:game,
                           ttb_main_seconds: nil,
                           ttb_extras_seconds: nil,
                           ttb_completionist_seconds: nil)
      component = described_class.new(game: bare)

      expect(component.hours).to eq(described_class::SAMPLE_HOURS)
    end

    it "uses the real IGDB values when present (not the sample)" do
      real = build_stubbed(:game,
                           ttb_main_seconds: 36_000,    # 10h
                           ttb_extras_seconds: 72_000,  # 20h
                           ttb_completionist_seconds: 144_000) # 40h
      component = described_class.new(game: real)

      expect(component.hours).to eq(main: 10, extras: 20, completionist: 40)
    end

    it "lets an explicit `hours:` kwarg trump both the game and the sample" do
      bare = build_stubbed(:game,
                           ttb_main_seconds: 0,
                           ttb_extras_seconds: 0,
                           ttb_completionist_seconds: 0)
      component = described_class.new(game: bare, hours: { main: 7, extras: 14, completionist: 21 })

      expect(component.hours).to eq(main: 7, extras: 14, completionist: 21)
    end

    it "renders SAMPLE_HOURS as labels when the game is fresh" do
      bare = build_stubbed(:game,
                           ttb_main_seconds: 0,
                           ttb_extras_seconds: 0,
                           ttb_completionist_seconds: 0)
      render_inline(described_class.new(game: bare, footage_hours: 5))
      # Bottom row carries the three "Nh" labels in order.
      labels = page.all('span.ttb-fuel-gauge__value--pillar').map { |el| el.text.strip }
      expect(labels).to eq([ "31h", "71h", "124h" ])
    end
  end

  # ------------------------------------------------------------------
  # HEAT_THRESHOLDS projection onto max_x. The same hour thresholds
  # (0 / 10 / 40 / 100) translate to different % positions depending on
  # the game's effort scale.
  # ------------------------------------------------------------------

  describe "HEAT_THRESHOLDS projection onto max_x (adaptive gradient)" do
    it "exposes the four documented thresholds in order" do
      expect(described_class::HEAT_THRESHOLDS).to eq(
        [
          [ 0,   "#4CAF50" ],
          [ 10,  "#CDDC39" ],
          [ 40,  "#FFB74D" ],
          [ 100, "#E91E63" ]
        ]
      )
    end

    it "small max_x (Pragmata ~23h): all colored stops compress, pink barely visible" do
      # completionist 22h → max_x = ceil(22 * 1.05) = 23
      tiny = build_stubbed(:game,
                           ttb_main_seconds:          5  * 3600,
                           ttb_extras_seconds:        12 * 3600,
                           ttb_completionist_seconds: 22 * 3600)
      component = described_class.new(game: tiny, footage_hours: 0)

      # max_x = 22 * 1.05 = 23.1 → rounded to 23
      expect(component.max_x).to eq(23)

      stops = component.gradient_stops
      # 0h → 0 %, 10h → 43.48 %, 40h → 100 % (clamped), 100h → 100 % (clamped).
      expect(stops).to include("#4CAF50 0.0%")
      expect(stops).to include("#CDDC39 43.48%")
      expect(stops).to include("#FFB74D 100%")
      expect(stops).to include("#E91E63 100%")
    end

    it "large max_x (Crimson Desert ~775h): pink dominates the right side" do
      # completionist 738h → max_x = ceil(738 * 1.05) = 775
      huge = build_stubbed(:game,
                           ttb_main_seconds:          31  * 3600,
                           ttb_extras_seconds:        71  * 3600,
                           ttb_completionist_seconds: 738 * 3600)
      component = described_class.new(game: huge, footage_hours: 0)

      expect(component.max_x).to eq(775)

      stops = component.gradient_stops
      # 0h → 0 %, 10h → ~1.29 %, 40h → ~5.16 %, 100h → ~12.9 %.
      # Green / lime / amber compress into the left ~13 %, pink owns the rest.
      expect(stops).to include("#4CAF50 0.0%")
      expect(stops).to include("#CDDC39 1.29%")
      expect(stops).to include("#FFB74D 5.16%")
      expect(stops).to include("#E91E63 12.9%")
    end

    it "appends an extension stop so the bar reaches 100 % on its own color" do
      huge = build_stubbed(:game,
                           ttb_main_seconds:          31  * 3600,
                           ttb_extras_seconds:        71  * 3600,
                           ttb_completionist_seconds: 738 * 3600)
      stops = described_class.new(game: huge, footage_hours: 0).gradient_stops

      # Last visible stop is `#E91E63 12.9%`; an extension `#E91E63 100%` is
      # appended so the bar's right edge doesn't fade past the gradient.
      expect(stops).to end_with("#E91E63 100%")
    end

    it "does NOT append an extension stop when the last threshold already projects to 100 %" do
      # max_x = ceil(100 * 1.05) = 105. 100h threshold → ~95.24 %.
      # ... still under 100, so the extension is added.
      # To exercise the "already at 100 %" branch we need a max_x where
      # 100h projects to >= 100 %: completionist of 95h (max_x = 100, then
      # 100/100 = 100 %).
      mid = build_stubbed(:game,
                           ttb_main_seconds:          10 * 3600,
                           ttb_extras_seconds:        40 * 3600,
                           ttb_completionist_seconds: 95 * 3600)
      component = described_class.new(game: mid, footage_hours: 0)

      # max_x = 95 * 1.05 = 99.75 → 100
      expect(component.max_x).to eq(100)
      stops = component.gradient_stops
      # 100h projects to 100 %, so no extension stop is appended.
      expect(stops.scan(/#E91E63 100%/).size).to eq(1)
    end

    it "thresholds anchor on HOURS, not on bar percentage" do
      # The 10h, 40h, 100h boundaries always express the same effort
      # intervals — they slide along the bar as max_x grows.
      small  = described_class.new(
        game: build_stubbed(:game,
                            ttb_main_seconds: 1 * 3600,
                            ttb_extras_seconds: 1 * 3600,
                            ttb_completionist_seconds: 50 * 3600)
      )
      large = described_class.new(
        game: build_stubbed(:game,
                            ttb_main_seconds: 1 * 3600,
                            ttb_extras_seconds: 1 * 3600,
                            ttb_completionist_seconds: 500 * 3600)
      )

      expect(small.gradient_stops).not_to eq(large.gradient_stops)
    end
  end

  # ------------------------------------------------------------------
  # pillar_label_data — the per-pillar tick metadata consumed by the
  # ERB to lay out the bottom row.
  # ------------------------------------------------------------------

  describe "#pillar_label_data" do
    it "returns one entry per pillar in PILLAR_KEYS order" do
      component = described_class.new(
        game: build_stubbed(:game,
                            ttb_main_seconds:          10 * 3600,
                            ttb_extras_seconds:        40 * 3600,
                            ttb_completionist_seconds: 100 * 3600)
      )
      keys = component.pillar_label_data.map { |entry| entry[:key] }
      expect(keys).to eq(described_class::PILLAR_KEYS)
      expect(keys).to eq([ :main, :extras, :completionist ])
    end

    it "carries the hours / label / position triplet on each entry" do
      component = described_class.new(
        game: build_stubbed(:game,
                            ttb_main_seconds:          10 * 3600,
                            ttb_extras_seconds:        40 * 3600,
                            ttb_completionist_seconds: 100 * 3600)
      )
      data = component.pillar_label_data

      expect(data[0]).to include(key: :main,          hours: 10,  label: "10h")
      expect(data[1]).to include(key: :extras,        hours: 40,  label: "40h")
      expect(data[2]).to include(key: :completionist, hours: 100, label: "100h")
    end

    it "renders an em-dash label for a missing pillar (hours == 0)" do
      component = described_class.new(
        game: build_stubbed(:game,
                            ttb_main_seconds:          0,
                            ttb_extras_seconds:        40 * 3600,
                            ttb_completionist_seconds: 100 * 3600),
        hours: { main: 0, extras: 40, completionist: 100 }
      )
      data = component.pillar_label_data

      expect(data[0][:label]).to eq("—")
      expect(data[0][:hours]).to eq(0)
    end

    it "stores a per-pillar `effective_position` that is the position when there's no collision" do
      # max_x = ceil(100 * 1.05) = 105.
      # main=10 → 9.524 %, extras=40 → 38.095 %, compl=100 → 95.238 %.
      # All gaps > 10 %, so nudge is nil and effective_position == position.
      component = described_class.new(
        game: build_stubbed(:game,
                            ttb_main_seconds:          10 * 3600,
                            ttb_extras_seconds:        40 * 3600,
                            ttb_completionist_seconds: 100 * 3600)
      )
      component.pillar_label_data.each do |entry|
        expect(entry[:nudge]).to be_nil
        expect(entry[:effective_position]).to eq(entry[:position])
      end
    end
  end

  # ------------------------------------------------------------------
  # Pillar bottom-label collision math — pull-apart shift.
  #
  # Calibration case: Crimson Desert (max_x ≈ 775h).
  #   main  31h → 4.0   % of 775
  #   extras71h → 9.161 % of 775
  #   gap = 5.16 % < 10 % → collision
  #   pull-apart → main:   4.0   - 1.3 = 2.7  %
  #                extras: 9.161 + 1.3 = 10.461 %
  # ------------------------------------------------------------------

  describe "pillar collision (BOTTOM_LABEL_COLLISION_THRESHOLD_PCT + NUDGE_PCT)" do
    let(:crimson_desert) do
      build_stubbed(:game,
                    ttb_main_seconds:          31  * 3600,
                    ttb_extras_seconds:        71  * 3600,
                    ttb_completionist_seconds: 738 * 3600)
    end

    it "exposes the collision threshold as 10 % of bar width" do
      expect(described_class::BOTTOM_LABEL_COLLISION_THRESHOLD_PCT).to eq(10.0)
    end

    it "exposes the nudge step as 1.3 % of bar width (post 2026-05-18 calibration)" do
      expect(described_class::NUDGE_PCT).to eq(1.3)
    end

    it "detects the main/extras collision (gap < 10 %)" do
      data = described_class.new(game: crimson_desert, footage_hours: 0).pillar_label_data
      main, extras, _compl = data

      expect((extras[:position] - main[:position]).abs).to be < described_class::BOTTOM_LABEL_COLLISION_THRESHOLD_PCT
      expect(main[:nudge]).to eq(:left)
      expect(extras[:nudge]).to eq(:right)
    end

    it "leaves completionist with no nudge (no collision near the bar's right edge)" do
      data = described_class.new(game: crimson_desert, footage_hours: 0).pillar_label_data
      compl = data[2]
      expect(compl[:nudge]).to be_nil
      # completionist 738h / 775 = 95.226 %
      expect(compl[:position]).to be_within(0.1).of(95.226)
      expect(compl[:effective_position]).to eq(compl[:position])
    end

    it "shifts the LEFT-anchored member of a colliding pair by -NUDGE_PCT" do
      data = described_class.new(game: crimson_desert, footage_hours: 0).pillar_label_data
      main = data[0]

      # main raw = 31/775 * 100 = 4.0 %
      # main effective = 4.0 - 1.3 = 2.7 %
      expect(main[:position]).to be_within(0.01).of(4.0)
      expect(main[:effective_position]).to be_within(0.01).of(2.7)
    end

    it "shifts the RIGHT-anchored member of a colliding pair by +NUDGE_PCT" do
      data = described_class.new(game: crimson_desert, footage_hours: 0).pillar_label_data
      extras = data[1]

      # extras raw = 71/775 * 100 = 9.161 %
      # extras effective = 9.161 + 1.3 = 10.461 %
      expect(extras[:position]).to be_within(0.01).of(9.161)
      expect(extras[:effective_position]).to be_within(0.01).of(10.461)
    end

    it "bakes the shifted positions into the rendered <span> left: style" do
      render_inline(described_class.new(game: crimson_desert, footage_hours: 0))

      main_span   = page.find('span.ttb-fuel-gauge__value--pillar[data-pillar="main"]')
      extras_span = page.find('span.ttb-fuel-gauge__value--pillar[data-pillar="extras"]')
      compl_span  = page.find('span.ttb-fuel-gauge__value--pillar[data-pillar="completionist"]')

      # main pulled LEFT (-1.3 %), extras pushed RIGHT (+1.3 %).
      expect(main_span["style"]).to match(/left:\s*2\.7%/)
      expect(extras_span["style"]).to match(/left:\s*10\.461%/)
      # completionist stays put.
      expect(compl_span["style"]).to match(/left:\s*95\.226%/)
    end

    it "clamps the leftward nudge so a near-zero label cannot push off the bar" do
      # main=0 → position 0; extras=1 → very close; compl=10.
      # max_x = max(10, 0, 10) * 1.05 = 11
      # main position 0 - 1.3 = -1.3 → clamped to 0.
      tiny = build_stubbed(:game,
                           ttb_main_seconds:          0,
                           ttb_extras_seconds:        1 * 3600,
                           ttb_completionist_seconds: 10 * 3600)
      data = described_class.new(game: tiny, footage_hours: 0).pillar_label_data

      main = data[0]
      expect(main[:nudge]).to eq(:left)
      expect(main[:effective_position]).to eq(0.0)
    end

    it "does NOT nudge when adjacent pillars are widely separated (gap >= 10 %)" do
      # max_x = ceil(100 * 1.05) = 105.
      # main 10h → 9.524 %, extras 50h → 47.619 %, compl 100h → 95.238 %.
      # All gaps > 10 %, no nudges.
      spaced = build_stubbed(:game,
                             ttb_main_seconds:          10 * 3600,
                             ttb_extras_seconds:        50 * 3600,
                             ttb_completionist_seconds: 100 * 3600)
      data = described_class.new(game: spaced, footage_hours: 0).pillar_label_data

      expect(data.map { |e| e[:nudge] }).to eq([ nil, nil, nil ])
      expect(data.map { |e| e[:effective_position] }).to eq(data.map { |e| e[:position] })
    end
  end

  # ------------------------------------------------------------------
  # I18n labels — pillar names, hours_short formatting, watermark,
  # footage caption, em-dash fallback. Asserted against the en
  # catalog values currently shipped.
  # ------------------------------------------------------------------

  describe "i18n labels" do
    it "resolves PILLAR labels via I18n keys games.ttb.*" do
      expect(described_class.pillar_label).to eq(
        main:          "main",
        extras:        "extras",
        completionist: "completionist"
      )
    end

    it "formats single-pillar labels via games.ttb.hours_short" do
      component = described_class.new(
        game: build_stubbed(:game,
                            ttb_main_seconds:          50 * 3600,
                            ttb_extras_seconds:        100 * 3600,
                            ttb_completionist_seconds: 200 * 3600)
      )
      expect(component.label_for(:main)).to eq("50h")
      expect(component.label_for(:extras)).to eq("100h")
      expect(component.label_for(:completionist)).to eq("200h")
    end

    it "falls back to common.em_dash for a missing pillar" do
      component = described_class.new(
        game: build_stubbed(:game),
        hours: { main: 0, extras: 0, completionist: 0 }
      )
      expect(component.label_for(:main)).to eq("—")
    end

    it "resolves the footage value label via games.ttb.hours_short" do
      component = described_class.new(game: build_stubbed(:game), footage_hours: 42)
      expect(component.footage_value_label).to eq("42h")
    end

    it "resolves the footage legend caption via games.ttb.footage" do
      component = described_class.new(game: build_stubbed(:game), footage_hours: 5)
      expect(component.footage_caption).to eq("footage")
    end

    it "renders the legend captions as their I18n strings" do
      render_inline(described_class.new(game: build_stubbed(:game, :synced), footage_hours: 10))
      legend = page.find('div.ttb-fuel-gauge__legend')
      expect(legend.text).to include("main")
      expect(legend.text).to include("extras")
      expect(legend.text).to include("completionist")
      expect(legend.text).to include("footage")
    end

    it "renders the TTB watermark via games.ttb.watermark" do
      render_inline(described_class.new(game: build_stubbed(:game, :synced), footage_hours: 0))
      expect(page).to have_css('span.ttb-fuel-gauge__title', text: "TTB")
    end
  end

  # ------------------------------------------------------------------
  # footage_label_alignment_class — left-align when footage_hours == 0,
  # centered otherwise.
  # ------------------------------------------------------------------

  describe "#footage_label_alignment_class" do
    it "returns --at-start when footage_hours is 0" do
      component = described_class.new(game: build_stubbed(:game), footage_hours: 0)
      expect(component.footage_label_alignment_class).to eq("ttb-fuel-gauge__label--at-start")
    end

    it "returns --centered when footage_hours is > 0" do
      component = described_class.new(game: build_stubbed(:game), footage_hours: 25)
      expect(component.footage_label_alignment_class).to eq("ttb-fuel-gauge__label--centered")
    end

    it "renders the at-start class on the footage label span when footage_hours == 0" do
      render_inline(described_class.new(game: build_stubbed(:game, :synced), footage_hours: 0))
      label = page.find('span.ttb-fuel-gauge__value--footage')
      expect(label[:class]).to include("ttb-fuel-gauge__label--at-start")
      expect(label.text.strip).to eq("0h")
    end

    it "renders the centered class on the footage label span when footage_hours > 0" do
      render_inline(described_class.new(game: build_stubbed(:game, :synced), footage_hours: 99))
      label = page.find('span.ttb-fuel-gauge__value--footage')
      expect(label[:class]).to include("ttb-fuel-gauge__label--centered")
      expect(label.text.strip).to eq("99h")
    end
  end

  # ------------------------------------------------------------------
  # Wave C reveal — stub-then-animate while `game.resyncing?` is true.
  #
  # While resyncing, every tick parks at the bar's left edge (left: 0)
  # and the bar's REAL adaptive gradient layer is hidden (opacity: 0)
  # so the STUB gradient layer (solid green via STUB_GRADIENT) shows
  # through. When the Turbo morph fires on sync complete the rendered
  # DOM no longer carries the stubbed positions / opacities; CSS
  # `transition: left 600ms ease-in-out` on the ticks plus
  # `transition: opacity 600ms ease-in-out` on the real layer
  # animate the gauge into its true state.
  #
  # The collision-detect math in `pillar_label_data` MUST be skipped
  # while resyncing — every entry parks at position 0.0 with no
  # nudge, so `effective_position` is also 0.0. This is what makes
  # the post-sync ticks animate cleanly from a single anchor.
  # ------------------------------------------------------------------

  describe "Wave C reveal — animated stub-then-reveal" do
    let(:resyncing_game) do
      build_stubbed(:game, :synced, resyncing: true)
    end

    let(:settled_game) do
      build_stubbed(:game, :synced, resyncing: false)
    end

    context "when game.resyncing? is true" do
      before do
        render_inline(described_class.new(game: resyncing_game, footage_hours: 50))
      end

      it "renders all 4 pillars at left: 0% (stubbed)" do
        # 3 pillar ticks + 1 footage tick = 4 marks on the bar, all
        # parked at the left edge while the resync is in flight.
        main_tick     = page.find('div.ttb-fuel-gauge__tick--main')
        extras_tick   = page.find('div.ttb-fuel-gauge__tick--extras')
        compl_tick    = page.find('div.ttb-fuel-gauge__tick--completionist')
        footage_tick  = page.find('div.ttb-fuel-gauge__tick--footage')

        expect(main_tick["style"]).to    match(/left:\s*0(\.0)?%/)
        expect(extras_tick["style"]).to  match(/left:\s*0(\.0)?%/)
        expect(compl_tick["style"]).to   match(/left:\s*0(\.0)?%/)
        expect(footage_tick["style"]).to match(/left:\s*0(\.0)?%/)
      end

      it "uses STUB_GRADIENT constant on the stub bar layer (not the adaptive one)" do
        stub_layer = page.find('div.ttb-fuel-gauge__bar-layer--stub')
        # STUB_GRADIENT = "#4CAF50 0%, #4CAF50 100%"
        expect(stub_layer["style"]).to include(described_class::STUB_GRADIENT)
        expect(stub_layer["style"]).to include("background-image: linear-gradient(to right, #{described_class::STUB_GRADIENT})")
      end

      it "real bar layer has opacity 0 (stub visible)" do
        real_layer = page.find('div.ttb-fuel-gauge__bar-layer--real')
        expect(real_layer["style"]).to match(/opacity:\s*0/)
      end

      it "pillar_label_data short-circuits — all 3 pillars at position: 0.0, effective_position: 0.0 (collision-detect NOT run)" do
        component = described_class.new(game: resyncing_game, footage_hours: 50)
        data = component.pillar_label_data

        expect(data.length).to eq(3)
        data.each do |entry|
          expect(entry[:position]).to eq(0.0)
          expect(entry[:effective_position]).to eq(0.0)
          expect(entry[:nudge]).to be_nil
        end
      end
    end

    context "when game.resyncing? is false" do
      before do
        render_inline(described_class.new(game: settled_game, footage_hours: 50))
      end

      it "renders pillars at computed real positions" do
        # `:synced` factory carries ttb_main=180000s (50h),
        # ttb_extras=360000s (100h), ttb_completionist=720000s (200h).
        # max_x = 200 * 1.05 = 210. main = 50/210 = 23.81 %.
        main_tick    = page.find('div.ttb-fuel-gauge__tick--main')
        extras_tick  = page.find('div.ttb-fuel-gauge__tick--extras')
        compl_tick   = page.find('div.ttb-fuel-gauge__tick--completionist')

        expect(main_tick["style"]).to    include("left: 23.81%")
        expect(extras_tick["style"]).to  include("left: 47.619%")
        expect(compl_tick["style"]).to   include("left: 95.238%")
      end

      it "real bar layer has opacity 1 (covers stub)" do
        real_layer = page.find('div.ttb-fuel-gauge__bar-layer--real')
        expect(real_layer["style"]).to match(/opacity:\s*1/)
      end

      it "pillar_label_data runs collision-detect math" do
        # Two pillars close together must trigger the nudge pass. Use
        # the Crimson Desert calibration case (main 31h ≈ 4 %,
        # extras 71h ≈ 9 % on a 775h max_x → gap < 10 % → collision).
        crimson = build_stubbed(:game,
                                resyncing: false,
                                ttb_main_seconds:          31  * 3600,
                                ttb_extras_seconds:        71  * 3600,
                                ttb_completionist_seconds: 738 * 3600)
        data = described_class.new(game: crimson, footage_hours: 0).pillar_label_data

        main, extras, compl = data
        expect(main[:nudge]).to eq(:left)
        expect(extras[:nudge]).to eq(:right)
        expect(compl[:nudge]).to be_nil

        # The nudge actually changed the rendered position.
        expect(main[:effective_position]).not_to eq(main[:position])
        expect(extras[:effective_position]).not_to eq(extras[:position])
        expect(compl[:effective_position]).to eq(compl[:position])
      end
    end
  end
end
