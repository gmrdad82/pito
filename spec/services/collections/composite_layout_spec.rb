require "rails_helper"

# Phase 27 §01h — pure layout engine spec. No DB, no fixtures, no IGDB
# CDN. Tiles are bare `Vips::Image.black(W, H)` blocks where the test
# needs a real Vips object; the rest of the assertions are arithmetic
# over `tile_boxes`.
RSpec.describe Collections::CompositeLayout do
  describe ".choose" do
    it "returns :empty for 0" do
      expect(described_class.choose(0)).to eq(:empty)
    end

    it "returns :passthrough for 1" do
      expect(described_class.choose(1)).to eq(:passthrough)
    end

    it "returns :pair for 2" do
      expect(described_class.choose(2)).to eq(:pair)
    end

    it "returns :netflix3 for 3" do
      expect(described_class.choose(3)).to eq(:netflix3)
    end

    it "returns :quad for 4" do
      expect(described_class.choose(4)).to eq(:quad)
    end

    it "returns :netflix5 for 5" do
      expect(described_class.choose(5)).to eq(:netflix5)
    end

    it "returns :six_grid for 6" do
      expect(described_class.choose(6)).to eq(:six_grid)
    end

    it "returns :six_grid for 7" do
      expect(described_class.choose(7)).to eq(:six_grid)
    end

    it "returns :six_grid for 100 (large overflow)" do
      expect(described_class.choose(100)).to eq(:six_grid)
    end

    it "raises ArgumentError on negative counts" do
      expect { described_class.choose(-1) }.to raise_error(ArgumentError, /non-negative/)
    end

    it "raises ArgumentError on non-Integer input (string)" do
      expect { described_class.choose("3") }.to raise_error(ArgumentError, /integer/)
    end

    it "raises ArgumentError on non-Integer input (float)" do
      expect { described_class.choose(3.0) }.to raise_error(ArgumentError, /integer/)
    end

    it "raises ArgumentError on nil" do
      expect { described_class.choose(nil) }.to raise_error(ArgumentError, /integer/)
    end
  end

  describe ".tile_boxes" do
    let(:w) { Collections::CompositeLayout::OUTPUT_WIDTH }
    let(:h) { Collections::CompositeLayout::OUTPUT_HEIGHT }

    it "returns [] for :empty" do
      expect(described_class.tile_boxes(:empty)).to eq([])
    end

    it "returns [] for :passthrough" do
      expect(described_class.tile_boxes(:passthrough)).to eq([])
    end

    it "raises ArgumentError on unknown layout symbol" do
      expect { described_class.tile_boxes(:bogus) }.to raise_error(ArgumentError, /unknown layout/)
    end

    describe ":pair" do
      let(:boxes) { described_class.tile_boxes(:pair) }

      it "returns 2 boxes" do
        expect(boxes.size).to eq(2)
      end

      it "tiles exactly to canvas width (98 → 49 + 49)" do
        expect(boxes.sum { |b| b[:w] }).to eq(w)
      end

      it "each box is full canvas height (130)" do
        expect(boxes.map { |b| b[:h] }).to all(eq(h))
      end

      it "left box origin is (0, 0)" do
        expect(boxes.first.slice(:x, :y)).to eq(x: 0, y: 0)
      end

      it "right box origin is (49, 0)" do
        expect(boxes.last.slice(:x, :y)).to eq(x: 49, y: 0)
      end

      it "no gap between tiles (left.x + left.w == right.x)" do
        expect(boxes[0][:x] + boxes[0][:w]).to eq(boxes[1][:x])
      end
    end

    describe ":netflix3" do
      let(:boxes) { described_class.tile_boxes(:netflix3) }

      it "returns 3 boxes" do
        expect(boxes.size).to eq(3)
      end

      it "big tile is 64 × 130" do
        expect(boxes[0].slice(:x, :y, :w, :h)).to eq(x: 0, y: 0, w: 64, h: 130)
      end

      it "top-right tile is 34 × 65 at (64, 0)" do
        expect(boxes[1].slice(:x, :y, :w, :h)).to eq(x: 64, y: 0, w: 34, h: 65)
      end

      it "bottom-right tile is 34 × 65 at (64, 65)" do
        expect(boxes[2].slice(:x, :y, :w, :h)).to eq(x: 64, y: 65, w: 34, h: 65)
      end

      it "row sums equal 98 (big 64 + right col 34)" do
        expect(boxes[0][:w] + boxes[1][:w]).to eq(w)
      end

      it "right column heights sum to 130" do
        expect(boxes[1][:h] + boxes[2][:h]).to eq(h)
      end
    end

    describe ":quad" do
      let(:boxes) { described_class.tile_boxes(:quad) }

      it "returns 4 boxes" do
        expect(boxes.size).to eq(4)
      end

      it "TL is 49 × 65 at (0, 0)" do
        expect(boxes[0].slice(:x, :y, :w, :h)).to eq(x: 0, y: 0, w: 49, h: 65)
      end

      it "TR is 49 × 65 at (49, 0)" do
        expect(boxes[1].slice(:x, :y, :w, :h)).to eq(x: 49, y: 0, w: 49, h: 65)
      end

      it "BL is 49 × 65 at (0, 65)" do
        expect(boxes[2].slice(:x, :y, :w, :h)).to eq(x: 0, y: 65, w: 49, h: 65)
      end

      it "BR is 49 × 65 at (49, 65)" do
        expect(boxes[3].slice(:x, :y, :w, :h)).to eq(x: 49, y: 65, w: 49, h: 65)
      end

      it "top row widths sum to 98" do
        expect(boxes[0][:w] + boxes[1][:w]).to eq(w)
      end

      it "bottom row widths sum to 98" do
        expect(boxes[2][:w] + boxes[3][:w]).to eq(w)
      end

      it "left column heights sum to 130" do
        expect(boxes[0][:h] + boxes[2][:h]).to eq(h)
      end

      it "right column heights sum to 130" do
        expect(boxes[1][:h] + boxes[3][:h]).to eq(h)
      end
    end

    describe ":netflix5" do
      let(:boxes) { described_class.tile_boxes(:netflix5) }

      it "returns 5 boxes" do
        expect(boxes.size).to eq(5)
      end

      it "big tile is 50 × 130 at (0, 0)" do
        expect(boxes[0].slice(:x, :y, :w, :h)).to eq(x: 0, y: 0, w: 50, h: 130)
      end

      it "TR cell 1 is 24 × 65 at (50, 0)" do
        expect(boxes[1].slice(:x, :y, :w, :h)).to eq(x: 50, y: 0, w: 24, h: 65)
      end

      it "TR cell 2 is 24 × 65 at (74, 0)" do
        expect(boxes[2].slice(:x, :y, :w, :h)).to eq(x: 74, y: 0, w: 24, h: 65)
      end

      it "BR cell 1 is 24 × 65 at (50, 65)" do
        expect(boxes[3].slice(:x, :y, :w, :h)).to eq(x: 50, y: 65, w: 24, h: 65)
      end

      it "BR cell 2 is 24 × 65 at (74, 65)" do
        expect(boxes[4].slice(:x, :y, :w, :h)).to eq(x: 74, y: 65, w: 24, h: 65)
      end

      it "big + right column sums to canvas width" do
        expect(boxes[0][:w] + boxes[1][:w] + boxes[2][:w]).to eq(w)
      end

      it "top row right column sums match bottom row" do
        expect(boxes[1][:w] + boxes[2][:w]).to eq(boxes[3][:w] + boxes[4][:w])
      end
    end

    describe ":six_grid" do
      let(:boxes) { described_class.tile_boxes(:six_grid) }

      it "returns 6 boxes" do
        expect(boxes.size).to eq(6)
      end

      it "top row sums to 98" do
        expect(boxes[0..2].sum { |b| b[:w] }).to eq(w)
      end

      it "bottom row sums to 98" do
        expect(boxes[3..5].sum { |b| b[:w] }).to eq(w)
      end

      it "leftmost column carries extra pixel (33 vs 32)" do
        # 98 / 3 = 32 base + 2 extras → cols 33, 33, 32.
        expect(boxes[0][:w]).to eq(33)
        expect(boxes[1][:w]).to eq(33)
        expect(boxes[2][:w]).to eq(32)
      end

      it "row heights are 65 each (130 / 2)" do
        expect(boxes[0][:h]).to eq(65)
        expect(boxes[3][:h]).to eq(65)
      end

      it "bottom row starts at y=65" do
        expect(boxes[3][:y]).to eq(65)
        expect(boxes[4][:y]).to eq(65)
        expect(boxes[5][:y]).to eq(65)
      end

      it "no gaps between columns (x flows left-to-right)" do
        expect(boxes[1][:x]).to eq(boxes[0][:x] + boxes[0][:w])
        expect(boxes[2][:x]).to eq(boxes[1][:x] + boxes[1][:w])
      end

      it "no overlap on the y axis (top.h == bot.y)" do
        expect(boxes[0][:y] + boxes[0][:h]).to eq(boxes[3][:y])
      end
    end

    describe "with non-default canvas (105 × 140 alternate)" do
      it "pair scales to half-and-half (52 / 53)" do
        boxes = described_class.tile_boxes(:pair, output_w: 105, output_h: 140)
        expect(boxes[0][:w]).to eq(52)
        expect(boxes[1][:w]).to eq(53)
        expect(boxes.first[:h]).to eq(140)
      end

      it "netflix3 scales to 70 + 35 (clean 2/3 split)" do
        boxes = described_class.tile_boxes(:netflix3, output_w: 105, output_h: 140)
        expect(boxes[0][:w]).to eq(70)
        expect(boxes[1][:w]).to eq(35)
        expect(boxes[2][:w]).to eq(35)
      end

      it "six_grid scales to 35 × 35 × 35 (clean integer split)" do
        boxes = described_class.tile_boxes(:six_grid, output_w: 105, output_h: 140)
        expect(boxes[0..2].map { |b| b[:w] }).to eq([ 35, 35, 35 ])
        expect(boxes.first[:h]).to eq(70)
      end

      it "netflix5 scales to 53 + 26 + 26 (right cells uniform)" do
        boxes = described_class.tile_boxes(:netflix5, output_w: 105, output_h: 140)
        expect(boxes[0][:w]).to eq(53)
        expect(boxes[1][:w]).to eq(26)
        expect(boxes[2][:w]).to eq(26)
      end
    end
  end

  describe ".compose" do
    let(:w) { Collections::CompositeLayout::OUTPUT_WIDTH }
    let(:h) { Collections::CompositeLayout::OUTPUT_HEIGHT }

    # Build a synthetic tile of the canonical source size (matches
    # `Composite::TileCache#fetch` returning a 227 × 320 IGDB tile).
    # `Vips::Image.black + new_from_image` produces a constant-colour
    # image we can resize / join into the target slot.
    def fake_tile(rgb: [ 100, 100, 100 ])
      Vips::Image.black(227, 320).new_from_image(rgb)
    end

    %i[pair netflix3 quad netflix5 six_grid].each do |layout|
      describe "layout #{layout}" do
        let(:slot_count) { described_class.tile_boxes(layout).size }
        let(:tiles)      { Array.new(slot_count) { fake_tile } }

        it "returns a Vips::Image" do
          expect(described_class.compose(layout, tiles)).to be_a(Vips::Image)
        end

        it "produces an image exactly OUTPUT_WIDTH × OUTPUT_HEIGHT" do
          img = described_class.compose(layout, tiles)
          expect(img.width).to eq(w)
          expect(img.height).to eq(h)
        end

        it "substitutes the placeholder block for nil entries" do
          with_nil = Array.new(slot_count) { nil }
          img = described_class.compose(layout, with_nil)
          expect(img.width).to eq(w)
          expect(img.height).to eq(h)
        end

        it "raises ArgumentError when tile count mismatches the layout" do
          short = Array.new(slot_count - 1) { fake_tile }
          expect { described_class.compose(layout, short) }
            .to raise_error(ArgumentError, /expected #{slot_count} tiles/)
        end

        it "is okay with a mix of real tiles and nil placeholders" do
          mixed = Array.new(slot_count) { |i| i.even? ? fake_tile : nil }
          img = described_class.compose(layout, mixed)
          expect(img.width).to eq(w)
          expect(img.height).to eq(h)
        end
      end
    end

    it "raises ArgumentError for :empty (caller is expected to short-circuit)" do
      expect { described_class.compose(:empty, []) }
        .to raise_error(ArgumentError, /does not compose/)
    end

    it "raises ArgumentError for :passthrough" do
      expect { described_class.compose(:passthrough, [ fake_tile ]) }
        .to raise_error(ArgumentError, /does not compose/)
    end
  end

  describe ".placeholder_tile" do
    it "returns a Vips::Image with the requested dimensions" do
      img = described_class.placeholder_tile(40, 60)
      expect(img.width).to eq(40)
      expect(img.height).to eq(60)
    end

    it "uses the locked BG_RGB [30, 30, 30] colour" do
      img = described_class.placeholder_tile(10, 10)
      # Sample the centre pixel; getpoint returns Array<Float> per band.
      pixel = img.getpoint(5, 5)
      expect(pixel.map(&:to_i)).to eq([ 30, 30, 30 ])
    end
  end
end
