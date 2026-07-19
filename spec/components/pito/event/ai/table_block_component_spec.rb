# frozen_string_literal: true

require "rails_helper"

# Pito::Event::Ai::TableBlockComponent renders an AI `table` block through the
# shared DataGridComponent, dressed in the kv-table palette (cyan leading
# column, dim values, right-aligned numerics/#ids/dates). This spec covers
# the smart per-column degrade added alongside the kv_table 20ch-cap removal:
# the leading #id-style column and any ALIGNING column (numeric, #id, or
# date/time — Pito::Event::Ai::CellShapes) are exempt from truncation; every
# other (prose) column is stamped .pito-table-cell--text, the class the
# compiled CSS (application.css — data-cols>=4 or a narrow @container) hooks
# the actual ellipsis behavior to. These are class/attribute-stamping specs
# only — the truncation itself is a compiled-CSS concern, proven via a
# scratch Tailwind build + grep (see the task report), not a Capybara/browser
# assertion here.
RSpec.describe Pito::Event::Ai::TableBlockComponent, type: :component do
  describe "leading + numeric columns are exempt from the text-cell class" do
    it "never stamps the leading #id-style column, even with long prose in it" do
      node = render_inline(described_class.new(
        header: [ "Game", "Genre", "Rating" ],
        rows:   [ [ "#38 TEKKEN 7: Bob, Negan & Lucille", "Fighting", "84" ] ]
      ))

      leading_cells = node.css(".pito-data-grid > span.text-cyan")
      expect(leading_cells).not_to be_empty
      leading_cells.each { |cell| expect(cell["class"]).not_to include("pito-table-cell--text") }
    end

    it "never stamps a column where every body cell reads as a number" do
      node = render_inline(described_class.new(
        header: [ "Channel", "Subs", "Views" ],
        rows:   [ [ "Main", "2.2K", "7,709" ], [ "Hard", "3", "93%" ] ]
      ))

      numeric_cells = node.css(".pito-data-grid > span.text-right")
      expect(numeric_cells).not_to be_empty
      numeric_cells.each { |cell| expect(cell["class"]).not_to include("pito-table-cell--text") }
    end
  end

  describe "id and date columns extend the alignment census (Pito::Event::Ai::CellShapes)" do
    it "right-aligns an all-#id column, header included" do
      node = render_inline(described_class.new(
        header: [ "#", "Game" ],
        rows:   [ [ "#38", "TEKKEN 7" ], [ "#1", "Elden Ring" ] ]
      ))

      id_header = node.css(".pito-data-grid > span").find { |c| c.text == "#" }
      id_cells  = node.css(".pito-data-grid > span").select { |c| c.text.match?(/\A#\d+\z/) }

      expect(id_header["class"]).to include("text-right")
      expect(id_cells).not_to be_empty
      id_cells.each { |cell| expect(cell["class"]).to include("text-right") }
    end

    it "right-aligns a date column mixing house shapes and a frozen DD-MM-YYYY cell" do
      node = render_inline(described_class.new(
        header: [ "Game", "Release" ],
        rows:   [
          [ "Elden Ring", "2 Jan" ],
          [ "TEKKEN 7", "19 Jul 12:00" ],
          [ "Old Game", "19-07-2026 12:00" ]
        ]
      ))

      release_header = node.css(".pito-data-grid > span").find { |c| c.text == "Release" }
      release_cells  = node.css(".pito-data-grid > span").select { |c| [ "2 Jan", "19 Jul 12:00", "19-07-2026 12:00" ].include?(c.text) }

      expect(release_header["class"]).to include("text-right")
      expect(release_cells.size).to eq(3)
      release_cells.each { |cell| expect(cell["class"]).to include("text-right") }
    end

    it "right-aligns a column mixing shape FAMILIES (#id + numeric + date cells)" do
      node = render_inline(described_class.new(
        header: [ "Game", "Value" ],
        rows:   [
          [ "Elden Ring", "#38" ],
          [ "TEKKEN 7", "7,709" ],
          [ "Old Game", "2 Jan" ]
        ]
      ))

      value_header = node.css(".pito-data-grid > span").find { |c| c.text == "Value" }
      value_cells  = node.css(".pito-data-grid > span").select { |c| [ "#38", "7,709", "2 Jan" ].include?(c.text) }

      expect(value_header["class"]).to include("text-right")
      expect(value_cells.size).to eq(3)
      value_cells.each { |cell| expect(cell["class"]).to include("text-right") }
    end

    it "leaves a prose column left-aligned" do
      node = render_inline(described_class.new(
        header: [ "Game", "Genre" ],
        rows:   [ [ "#1 Elden Ring", "RPG" ], [ "#2 Sekiro", "Action RPG" ] ]
      ))

      genre_header = node.css(".pito-data-grid > span").find { |c| c.text == "Genre" }
      expect(genre_header["class"]).not_to include("text-right")
    end

    it "leaves a mixed prose+id column left-aligned (not every cell shapes)" do
      node = render_inline(described_class.new(
        header: [ "Game", "Linked" ],
        rows:   [ [ "Elden Ring", "#1" ], [ "Sekiro", "unlinked" ] ]
      ))

      linked_header = node.css(".pito-data-grid > span").find { |c| c.text == "Linked" }
      expect(linked_header["class"]).not_to include("text-right")
    end
  end

  describe "prose columns get the degrade-first class" do
    it "stamps a non-leading, non-numeric column on both the header and body cells" do
      node = render_inline(described_class.new(
        header: [ "Game", "Genre", "Rating" ],
        rows:   [ [ "#1 Elden Ring", "RPG", "84" ] ]
      ))

      genre_header = node.css(".pito-data-grid > span").find { |c| c.text == "Genre" }
      genre_cell   = node.css(".pito-data-grid > span").find { |c| c.text == "RPG" }

      expect(genre_header["class"]).to include("pito-table-cell--text")
      expect(genre_cell["class"]).to include("pito-table-cell--text")
    end

    it "stamps the flexible column on a 2-column table too (count-based truncation is CSS-only)" do
      node = render_inline(described_class.new(
        header: [ "Game", "Genre" ],
        rows:   [ [ "#1 Elden Ring", "Action RPG" ] ]
      ))

      genre_cell = node.css(".pito-data-grid > span").find { |c| c.text == "Action RPG" }
      expect(genre_cell["class"]).to include("pito-table-cell--text")
    end
  end

  describe "data-cols attribute" do
    it "carries the header's column count for the CSS column-pressure gate" do
      node = render_inline(described_class.new(
        header: [ "Game", "Genre", "Developer", "Rating" ],
        rows:   [ [ "#1 Elden Ring", "RPG", "FromSoftware", "94" ] ]
      ))

      expect(node.at_css(".pito-data-grid")["data-cols"]).to eq("4")
    end

    it "floors at 2 columns even for a single-column header" do
      node = render_inline(described_class.new(header: [ "Game" ], rows: [ [ "#1 Elden Ring" ] ]))

      expect(node.at_css(".pito-data-grid")["data-cols"]).to eq("2")
    end
  end
end
