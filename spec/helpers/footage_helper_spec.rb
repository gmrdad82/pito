require "rails_helper"

RSpec.describe FootageHelper, type: :helper do
  describe "#human_filesize" do
    # Foundation work for the Wave 2 footage table expansion: the project
    # show page renders bytes via this helper; the importer (CLI) writes
    # the underlying integer. Empty / zero / nil collapse to the em-dash
    # placeholder Pito uses for "no value" in tables.
    {
      nil      => "—",
      0        => "—",
      1024     => "1 KB",
      12_345   => "12.06 KB",
      1_024_000 => "1000 KB",
      302_000_000  => "288.01 MB",
      1_073_741_824 => "1 GB"
    }.each do |bytes, expected|
      it "renders #{bytes.inspect} as #{expected.inspect}" do
        expect(helper.human_filesize(bytes)).to eq(expected)
      end
    end
  end

  describe "#human_duration" do
    # Foundation work for the Wave 2 footage table expansion: the project
    # show page renders the duration column via this helper. nil / non-positive
    # values collapse to the em-dash placeholder (mirrors `human_filesize`).
    {
      nil   => "—",
      0     => "—",
      -5    => "—",
      1     => "1s",
      45    => "45s",
      59    => "59s",
      60    => "1m 0s",
      90    => "1m 30s",
      599   => "9m 59s",
      622   => "10m 22s",
      3599  => "59m 59s",
      3600  => "1h 0m 0s",
      3661  => "1h 1m 1s",
      5415  => "1h 30m 15s",
      86_400 => "24h 0m 0s"
    }.each do |seconds, expected|
      it "renders #{seconds.inspect} as #{expected.inspect}" do
        expect(helper.human_duration(seconds)).to eq(expected)
      end
    end

    it "coerces float / decimal input via to_i" do
      expect(helper.human_duration(622.7)).to eq("10m 22s")
      expect(helper.human_duration(BigDecimal("622.0"))).to eq("10m 22s")
    end
  end

  describe "#human_fps" do
    # Industry-standard fps values + integer-equivalent collapse. Mirrors
    # the project workspace footage table's fps column rendering.
    {
      nil               => "—",
      0                 => "—",
      0.0               => "—",
      -1                => "—",
      24                => "24",
      24.0              => "24",
      30                => "30",
      30.0              => "30",
      60                => "60",
      60.0              => "60",
      120               => "120",
      23.976            => "23.97",
      29.97             => "29.97",
      59.94             => "59.94",
      50.5              => "50.50",
      48.123            => "48.12"
    }.each do |input, expected|
      it "renders #{input.inspect} as #{expected.inspect}" do
        expect(helper.human_fps(input)).to eq(expected)
      end
    end

    it "handles BigDecimal('60.000') as `60` (integer-equivalent collapse)" do
      # Real Footage rows store fps as a `decimal` column → BigDecimal.
      # BigDecimal('60.000').to_f returns 60.0; the integer-equivalent
      # branch fires within the ±0.001 tolerance and the value renders
      # as the integer string.
      expect(helper.human_fps(BigDecimal("60.000"))).to eq("60")
    end

    it "handles BigDecimal('29.970') as `29.97` (industry-standard match)" do
      # 29.97 NTSC. The fuzzy match tolerates BigDecimal noise.
      expect(helper.human_fps(BigDecimal("29.970"))).to eq("29.97")
    end

    it "handles BigDecimal('23.976') as `23.97`" do
      expect(helper.human_fps(BigDecimal("23.976"))).to eq("23.97")
    end
  end

  describe "#human_source" do
    {
      nil      => "—",
      ""       => "—",
      "obs"    => "OBS",
      "camera" => "Camera"
    }.each do |input, expected|
      it "renders #{input.inspect} as #{expected.inspect}" do
        expect(helper.human_source(input)).to eq(expected)
      end
    end

    it "falls back to titleize for unknown enum values" do
      # New enum members render via `titleize` until they get a canonical
      # entry in `SOURCE_LABELS`. Keeps the surface stable when the schema
      # gains a value before the label table catches up.
      expect(helper.human_source("screen_recorder")).to eq("Screen Recorder")
    end

    it "coerces non-string input via to_s" do
      expect(helper.human_source(:obs)).to eq("OBS")
    end
  end

  describe "#filename_truncate_middle" do
    # Server-side fixed-length middle truncation. Replaces the prior
    # `filename_split` two-span CSS-flex pattern. Defaults are
    # head=8 / tail=12 / ellipsis=`…` (Unicode U+2026, single character).
    # Output: `<first 8 chars>…<last 12 chars>` for inputs longer than
    # `head + 1 + tail` = 21 chars; otherwise the input is returned as-is.

    it "returns the full filename when shorter than head + 1 + tail" do
      expect(helper.filename_truncate_middle("clip.mkv")).to eq("clip.mkv")
    end

    it "returns the full filename when exactly at the boundary (21 chars)" do
      # Default boundary is 8 + 1 + 12 = 21 chars. At-or-below renders
      # as-is; the truncation branch only fires for length > 21.
      name = "a" * 21
      expect(name.length).to eq(21)
      expect(helper.filename_truncate_middle(name)).to eq(name)
    end

    it "truncates a 22-character filename (one over the boundary)" do
      # 22 chars trips the truncation branch. Output is 8 + 1 + 12 = 21
      # chars: first 8 + ellipsis + last 12.
      name = "a" * 22
      result = helper.filename_truncate_middle(name)
      expect(result).to eq("#{'a' * 8}…#{'a' * 12}")
      expect(result.length).to eq(21)
    end

    it "renders the user's example exactly as `Ghost 'n…23-11-43.mkv`" do
      # The defining example from the spec: a 55-char OBS-style filename
      # collapses to a 21-char compact form.
      name = "Ghost 'n Goblins Resurrection - 2026-04-23 23-11-43.mkv"
      expect(name.length).to eq(55)
      expect(helper.filename_truncate_middle(name)).to eq("Ghost 'n…23-11-43.mkv")
    end

    it "uses a Unicode ellipsis (U+2026), not three ASCII dots" do
      name = "Ghost 'n Goblins Resurrection - 2026-04-23 23-11-43.mkv"
      result = helper.filename_truncate_middle(name)
      expect(result).to include("…")
      expect(result).not_to include("...")
      # Confirm exact codepoint at the seam (after the 8-char head).
      expect(result[8].ord).to eq(0x2026)
    end

    it "honors custom head / tail args" do
      name = "abcdefghij-1234567890.mkv" # 25 chars
      # head=4 / tail=8 -> first 4 + … + last 8 = 13 chars output.
      result = helper.filename_truncate_middle(name, head: 4, tail: 8)
      expect(result).to eq("abcd…7890.mkv")
      expect(result.length).to eq(13)
    end

    it "honors custom head / tail args at their boundary (no truncation)" do
      # head=4 / tail=8 -> boundary is 13. A 13-char input renders as-is.
      expect(helper.filename_truncate_middle("clip-1234.mkv", head: 4, tail: 8)).to eq("clip-1234.mkv")
    end

    it "handles multibyte / unicode filenames without UTF-8 boundary corruption" do
      # Ruby String#[] is character-based on UTF-8 strings; the helper
      # must not slice mid-codepoint. Each multi-byte char survives as
      # a single character in the output and the result stays valid
      # UTF-8 end-to-end.
      name = "Café-session-é-2026-04-23-23-34-48.mkv" # 38 chars
      result = helper.filename_truncate_middle(name)
      expect(result.length).to eq(21)
      # head = first 8 characters of "Café-session-..." -> "Café-ses"
      expect(result).to start_with("Café-ses")
      expect(result).to include("…")
      # tail = last 12 characters -> "3-23-34-48.mkv" trailing slice.
      expect(result).to end_with(name[-12..])
      expect(result.encoding).to eq(Encoding::UTF_8)
      expect(result).to be_valid_encoding
    end

    it "returns empty string for nil input" do
      expect(helper.filename_truncate_middle(nil)).to eq("")
    end

    it "returns empty string for empty input" do
      expect(helper.filename_truncate_middle("")).to eq("")
    end
  end
end
