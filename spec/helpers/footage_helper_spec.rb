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

  describe "#filename_split" do
    it "returns the full filename and empty tail when shorter than the tail length" do
      expect(helper.filename_split("clip.mp4")).to eq([ "clip.mp4", "" ])
    end

    it "returns the full filename and empty tail when exactly at the tail length" do
      name = "a" * FootageHelper::FOOTAGE_FILENAME_TAIL
      expect(helper.filename_split(name)).to eq([ name, "" ])
    end

    it "splits OBS-style filenames so the timestamp + extension stay in the tail" do
      name = "Ghost 'n Goblins Resurrection - 2026-04-23 23-34-48.mkv"
      head, tail = helper.filename_split(name)
      # Default tail is 23 characters — covers ` - YYYY-MM-DD HH-MM-SS.mkv`
      # tail end. The seconds + extension must end up in the tail span.
      expect(tail.length).to eq(FootageHelper::FOOTAGE_FILENAME_TAIL)
      expect(tail).to end_with("23-34-48.mkv")
      expect(head + tail).to eq(name)
      expect(head).to start_with("Ghost 'n Goblins")
    end

    it "honors a custom tail length" do
      head, tail = helper.filename_split("hello-world.mkv", tail: 4)
      expect(tail).to eq(".mkv")
      expect(head).to eq("hello-world")
    end

    it "handles multibyte head portions without losing characters" do
      # The head contains a multi-byte character; splitting must not
      # corrupt the string — the concatenation of head + tail must
      # equal the original input byte-for-byte.
      name = "Café session – 2026-04-23 23-34-48.mkv"
      head, tail = helper.filename_split(name)
      expect(head + tail).to eq(name)
      expect(tail).to end_with("23-34-48.mkv")
    end

    it "coerces non-string input via to_s (defensive — nil renders as empty)" do
      expect(helper.filename_split(nil)).to eq([ "", "" ])
    end
  end
end
