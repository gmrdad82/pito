# frozen_string_literal: true

require "rails_helper"

# Ai::BlockCutter is the pure incremental scanner under P13 block streaming:
# it receives arbitrary fragments of the streaming pito_respond arguments
# JSON and cuts each complete top-level block object the moment it closes,
# regardless of where the fragment boundaries fall. Every cut string must
# JSON.parse back to the block the payload carried; malformed input must
# never raise — the cutter just stops yielding.
RSpec.describe Ai::BlockCutter do
  subject(:cutter) { described_class.new }

  # Three blocks that exercise the traps at once: braces and commas inside
  # string values, nested objects (kv rows), and nested arrays (chart data).
  let(:blocks) do
    [
      { "type" => "text", "text" => "a { b } c, and {more, commas}" },
      { "type" => "kv_table",
        "rows" => [ { "key" => "views", "value" => { "v" => "1234", "format" => "number" } } ] },
      { "type" => "chart", "viz" => "bar",
        "data" => { "bars" => [ { "label" => "wk {1}", "pct" => 42.5 }, { "label" => "wk 2", "pct" => 7 } ] } }
    ]
  end
  let(:payload) { JSON.generate({ "blocks" => blocks }) }

  def parsed(strings)
    strings.map { |s| JSON.parse(s) }
  end

  describe "whole payload in one fragment" do
    it "cuts every block, each parsing to the original" do
      cutter << payload
      out = cutter.take_blocks

      expect(out.length).to eq(3)
      expect(parsed(out)).to eq(blocks)
    end
  end

  describe "one-byte-at-a-time feed" do
    it "cuts the same blocks as the one-fragment feed" do
      payload.each_char { |char| cutter << char }

      expect(parsed(cutter.take_blocks)).to eq(blocks)
    end
  end

  describe "every possible two-fragment split" do
    it "yields identical blocks at every split point" do
      (1...payload.length).each do |i|
        c = described_class.new
        c << payload[0...i] << payload[i..]

        expect(parsed(c.take_blocks)).to eq(blocks), "diverged when split at byte #{i}"
      end
    end
  end

  describe "split mid-string" do
    it "reassembles a string value cut between fragments" do
      raw = '{"blocks": [{"type": "text", "text": "hello world"}]}'
      mid = raw.index("hello") + 3
      cutter << raw[0...mid] << raw[mid..]

      expect(parsed(cutter.take_blocks)).to eq([ { "type" => "text", "text" => "hello world" } ])
    end
  end

  describe "split mid-escape" do
    it 'handles \\" straddling two fragments' do
      raw = '{"blocks": [{"type": "text", "text": "say \"hi\" now"}]}'
      mid = raw.index("\\") + 1 # fragment 1 ends on the backslash, fragment 2 starts on the quote
      cutter << raw[0...mid] << raw[mid..]

      expect(parsed(cutter.take_blocks)).to eq([ { "type" => "text", "text" => 'say "hi" now' } ])
    end
  end

  describe "split mid-unicode-escape" do
    it "handles \\uXXXX straddling two fragments" do
      raw = '{"blocks": [{"type": "text", "text": "caf\u00e9 open"}]}' # single-quoted: literal \\u00e9 chars
      mid = raw.index("\\u00") + 3 # split inside the four hex digits
      cutter << raw[0...mid] << raw[mid..]

      expect(parsed(cutter.take_blocks)).to eq([ { "type" => "text", "text" => "café open" } ])
    end
  end

  describe "nested objects and arrays inside a block" do
    it "cuts a kv_table with row objects and a chart with array data as single blocks" do
      cutter << payload
      out = cutter.take_blocks

      expect(parsed(out)[1]).to eq(blocks[1])
      expect(parsed(out)[2]).to eq(blocks[2])
    end
  end

  describe "braces inside string values" do
    it "does not cut on a { or } that lives inside a string" do
      cutter << '{"blocks": [{"type": "text", "text": "a { b } c"}]}'

      expect(parsed(cutter.take_blocks)).to eq([ { "type" => "text", "text" => "a { b } c" } ])
    end
  end

  describe "commas inside strings" do
    it "does not treat a quoted comma as a block separator" do
      cutter << '{"blocks": [{"type": "text", "text": "one, two, three"}]}'

      expect(parsed(cutter.take_blocks)).to eq([ { "type" => "text", "text" => "one, two, three" } ])
    end
  end

  describe "whitespace between blocks" do
    it "cuts a pretty-printed payload identically" do
      cutter << JSON.pretty_generate({ "blocks" => blocks })

      expect(parsed(cutter.take_blocks)).to eq(blocks)
    end
  end

  describe "empty blocks array" do
    it "yields nothing for [] and does not raise" do
      cutter << '{"blocks": []}'

      expect(cutter.take_blocks).to eq([])
    end

    it "yields nothing for a whitespace-only array" do
      cutter << "{\"blocks\": [ \n ]}"

      expect(cutter.take_blocks).to eq([])
    end
  end

  describe "trailing content after ]" do
    it "ignores everything after the array closes" do
      cutter << '{"blocks": [{"type": "text", "text": "x"}]} {"blocks": [{"type": "text", "text": "ghost"}]}'

      expect(parsed(cutter.take_blocks)).to eq([ { "type" => "text", "text" => "x" } ])
    end

    it "never cuts a block out of a sibling value after the array" do
      cutter << '{"blocks": [{"type": "text", "text": "x"}], "tail": {"a": [{"b": 1}]}}'

      expect(parsed(cutter.take_blocks)).to eq([ { "type" => "text", "text" => "x" } ])
    end
  end

  describe "#take_blocks draining" do
    it "returns [] on a second immediate call" do
      cutter << payload

      expect(cutter.take_blocks.length).to eq(3)
      expect(cutter.take_blocks).to eq([])
    end

    it "yields each block as soon as it closes, across calls" do
      first_json = JSON.generate(blocks[0])
      first_end  = payload.index(first_json) + first_json.length - 1 # through block 0's closing brace
      cutter << payload[0..first_end]
      expect(parsed(cutter.take_blocks)).to eq([ blocks[0] ])

      cutter << payload[(first_end + 1)..]
      expect(parsed(cutter.take_blocks)).to eq(blocks[1..])
    end
  end

  describe "malformed input" do
    it "yields nothing for non-JSON garbage and does not raise" do
      expect {
        cutter << "!!! this is not json at all !!!"
      }.not_to raise_error

      expect(cutter.take_blocks).to eq([])
    end

    it "does not raise on stray structural characters" do
      expect {
        cutter << "]}}{{[" << "," << "]"
      }.not_to raise_error

      expect(cutter.take_blocks).to eq([])
    end

    it "goes dead on a non-object array element instead of guessing" do
      cutter << '{"blocks": ["bare string", {"type": "text", "text": "x"}]}'

      expect(cutter.take_blocks).to eq([])
    end

    it "does not raise on nil" do
      expect { cutter << nil }.not_to raise_error

      expect(cutter.take_blocks).to eq([])
    end
  end

  describe "content before the array" do
    it "ignores a [ inside a string value ahead of the blocks array" do
      # Not a shape pito_respond emits (blocks is the only key), but the
      # depth-1 heuristic must not trip on quoted brackets while hunting.
      cutter << '{"note": "not [ an ] array", "blocks": [{"type": "text", "text": "x"}]}'

      expect(parsed(cutter.take_blocks)).to eq([ { "type" => "text", "text" => "x" } ])
    end
  end

  describe "#<<" do
    it "returns self for chaining" do
      expect(cutter << "{").to be(cutter)
    end
  end

  describe "take_partial" do
    let(:kv_payload) { '{"blocks": [{"type":"kv_table","rows":[["a","1"],["b","2"]]}]}' }

    it "snapshots each array row as it closes, re-arming after the next" do
      first_close  = kv_payload.index('["a","1"]') + '["a","1"]'.length - 1
      second_close = kv_payload.index('["b","2"]') + '["b","2"]'.length - 1

      kv_payload[0..first_close].each_char { |char| cutter << char }
      expect(JSON.parse(cutter.take_partial)).to eq({ "type" => "kv_table", "rows" => [ [ "a", "1" ] ] })

      cutter << kv_payload[(first_close + 1)..second_close]
      expect(JSON.parse(cutter.take_partial))
        .to eq({ "type" => "kv_table", "rows" => [ [ "a", "1" ], [ "b", "2" ] ] })
    end

    it "is nil once the block's own cut lands, even though a row boundary fired mid-stream" do
      cutter << kv_payload

      expect(cutter.take_partial).to be_nil
      expect(parsed(cutter.take_blocks))
        .to eq([ { "type" => "kv_table", "rows" => [ [ "a", "1" ], [ "b", "2" ] ] } ])
      expect(cutter.take_partial).to be_nil
    end

    it "snapshots an object row the same way as an array row" do
      payload = '{"blocks": [{"type":"kv_table","rows":' \
                '[{"key":"Rating","value":"84"},{"key":"Genre","value":"RPG"}]}]}'
      first_row = '{"key":"Rating","value":"84"}'
      close = payload.index(first_row) + first_row.length - 1
      payload[0..close].each_char { |char| cutter << char }

      expect(JSON.parse(cutter.take_partial)["rows"]).to eq([ { "key" => "Rating", "value" => "84" } ])
    end

    it "does not fire on a nested value object closing inside a still-open row" do
      payload = '{"blocks": [{"type":"table","header":["A"],"rows":[["1",{"v":2,"format":"number"}]]}]}'
      typed_value = '{"v":2,"format":"number"}'
      value_close = payload.index(typed_value) + typed_value.length - 1
      payload[0..value_close].each_char { |char| cutter << char }

      partial = cutter.take_partial
      expect(partial.nil? || JSON.parse(partial)["rows"].to_a.empty?).to be(true)

      row = %(["1",#{typed_value}])
      row_close = payload.index(row) + row.length - 1
      cutter << payload[(value_close + 1)..row_close]

      expect(JSON.parse(cutter.take_partial)).to eq(
        { "type" => "table", "header" => [ "A" ], "rows" => [ [ "1", { "v" => 2, "format" => "number" } ] ] }
      )
    end

    it "never fires on ] } [ characters that live inside a string" do
      payload = '{"blocks": [{"type":"text","text":"a ] b } c [["}]}'
      payload.each_char do |char|
        cutter << char
        expect(cutter.take_partial).to be_nil
      end
    end

    describe "split-boundary sweep" do
      it "yields the same first-row partial regardless of 3-char chunk phase" do
        first_close = kv_payload.index('["a","1"]') + '["a","1"]'.length - 1
        expected = { "type" => "kv_table", "rows" => [ [ "a", "1" ] ] }

        (0..2).each do |phase|
          c = described_class.new
          chunks = phase.positive? ? [ kv_payload[0...phase] ] : []
          chunks.concat(kv_payload[phase..].each_char.each_slice(3).map(&:join))

          fed = 0
          partial = nil
          chunks.each do |chunk|
            c << chunk
            fed += chunk.length
            partial ||= c.take_partial if fed > first_close
          end

          expect(JSON.parse(partial)).to eq(expected), "diverged at chunk phase #{phase}"
        end
      end
    end
  end
end
