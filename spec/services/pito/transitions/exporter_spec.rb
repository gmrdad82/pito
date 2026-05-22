require "rails_helper"

RSpec.describe Pito::Transitions::Exporter do
  describe ".render_css_block" do
    let(:block) { described_class.render_css_block }

    it "is wrapped by the open + close sentinels" do
      expect(block).to start_with(described_class::SENTINEL_OPEN)
      expect(block).to include(described_class::SENTINEL_CLOSE)
    end

    it "declares every token as a --tui-trn-* custom property" do
      Pito::Transitions::Tokens::ALL.each_key do |key|
        css_name = "--tui-trn-#{key.to_s.tr('_', '-')}"
        expect(block).to include(css_name)
      end
    end

    it "renders the 8 token names" do
      lines = block.lines.grep(/--tui-trn-/)
      expect(lines.size).to eq(8)
    end

    it "appends ms suffix on duration tokens" do
      expect(block).to include("--tui-trn-scramble-duration-ms: 200ms;")
      expect(block).to include("--tui-trn-color-crossfade-duration-ms: 300ms;")
      expect(block).to include("--tui-trn-shimmer-cycle-ms: 1600ms;")
      expect(block).to include("--tui-trn-debounce-ms: 80ms;")
    end

    it "renders the easing token as a bare CSS value" do
      expect(block).to include("--tui-trn-color-crossfade-easing: ease-out;")
    end

    it "renders the shimmer gradient stops token as a CSS value" do
      expect(block).to include("--tui-trn-shimmer-gradient-stops: muted 0%, muted 40%, accent 50%, muted 60%, muted 100%;")
    end
  end

  describe ".render_rust_block" do
    let(:block) { described_class.render_rust_block }

    it "starts with the auto-generated header comment" do
      expect(block).to start_with("// >>> TRANSITIONS_TOKENS auto-generated")
    end

    it "declares 8 pub const lines" do
      lines = block.lines.grep(/^pub const /)
      expect(lines.size).to eq(8)
    end

    it "uses u32 for Integer tokens" do
      expect(block).to include("pub const SCRAMBLE_DURATION_MS: u32 = 200;")
      expect(block).to include("pub const DEBOUNCE_MS: u32 = 80;")
    end

    it "uses &'static str for String tokens" do
      expect(block).to include("pub const COLOR_CROSSFADE_EASING: &'static str = \"ease-out\";")
      expect(block).to include("pub const SHIMMER_GRADIENT_STOPS: &'static str = \"muted 0%, muted 40%, accent 50%, muted 60%, muted 100%\";")
    end
  end

  describe ".write_or_replace" do
    let(:tmp_path) { Rails.root.join("tmp/test_transitions_exporter.css") }

    before { tmp_path.delete if tmp_path.exist? }
    after  { tmp_path.delete if tmp_path.exist? }

    it "appends the block when sentinels are absent" do
      tmp_path.write("/* preexisting */\n")
      described_class.write_or_replace(tmp_path, described_class.render_css_block)
      content = tmp_path.read
      expect(content).to include("/* preexisting */")
      expect(content).to include(described_class::SENTINEL_OPEN)
      expect(content).to include(described_class::SENTINEL_CLOSE)
    end

    it "replaces the block in place when sentinels are present" do
      tmp_path.write("/* preexisting */\n" + described_class.render_css_block)
      first = tmp_path.read
      described_class.write_or_replace(tmp_path, described_class.render_css_block)
      second = tmp_path.read
      expect(first).to eq(second)
    end

    it "is idempotent across repeated calls" do
      described_class.write_or_replace(tmp_path, described_class.render_css_block)
      after_first = tmp_path.read
      described_class.write_or_replace(tmp_path, described_class.render_css_block)
      after_second = tmp_path.read
      expect(after_first).to eq(after_second)
    end
  end

  describe ".export_css! + .export_rust!" do
    it "is idempotent — running twice yields the same bytes" do
      described_class.export_css!
      described_class.export_rust!
      css_hash_one = Digest::MD5.hexdigest(described_class::CSS_PATH.read)
      rust_hash_one = Digest::MD5.hexdigest(described_class::RUST_PATH.read)

      described_class.export_css!
      described_class.export_rust!
      css_hash_two = Digest::MD5.hexdigest(described_class::CSS_PATH.read)
      rust_hash_two = Digest::MD5.hexdigest(described_class::RUST_PATH.read)

      expect(css_hash_one).to eq(css_hash_two)
      expect(rust_hash_one).to eq(rust_hash_two)
    end
  end
end
