# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::DataGridComponent, type: :component do
  def render_grid(heading_cells: [], rows: [], col_count: 2, fixed_leading: 0,
                  fixed_trailing: 0, has_body: false, info_lines: [])
    render_inline(described_class.new(heading_cells:, rows:, col_count:, fixed_leading:,
                                      fixed_trailing:, has_body:, info_lines:))
  end

  let(:rows) do
    [ [ { text: "alpha", class: "text-cyan", html: false, data: nil },
        { text: "1",     class: "text-fg",   html: false, data: nil } ] ]
  end

  it "renders the grid with cols and pinned-column data attributes" do
    node = render_grid(rows:, col_count: 3, fixed_leading: 1, fixed_trailing: 2)
    grid = node.css(".pito-data-grid").first
    expect(grid["data-cols"]).to eq("3")
    expect(grid["data-fixed-leading"]).to eq("1")
    expect(grid["data-fixed-trailing"]).to eq("2")
  end

  it "renders nothing at all for no rows and no info lines" do
    expect(render_grid.to_html.strip).to eq("")
  end

  it "adds the top-border separator classes only when a body is present" do
    with    = render_grid(rows:, has_body: true).css(".pito-data-grid").first["class"]
    without = render_grid(rows:, has_body: false).css(".pito-data-grid").first["class"]
    expect(with).to include("mt-2", "border-t", "pt-2")
    expect(without).not_to include("border-t")
  end

  it "renders heading spans before the row cells" do
    node  = render_grid(heading_cells: [ { text: "Name", class: "text-fg-dim" } ], rows:)
    spans = node.css(".pito-data-grid > span")
    expect(spans.first.text).to eq("Name")
    expect(spans.first["class"]).to eq("text-fg-dim")
    expect(spans.map(&:text)).to eq(%w[Name alpha 1])
  end

  it "escapes plain cells and renders html cells raw" do
    node = render_grid(rows: [ [
      { text: "<b>x</b>", class: "c", html: false, data: nil },
      { text: "<b>y</b>", class: "c", html: true,  data: nil }
    ] ])
    spans = node.css(".pito-data-grid > span")
    expect(spans[0].css("b")).to be_empty
    expect(spans[1].css("b").text).to eq("y")
  end

  it "carries per-cell data attributes (the chat-prefill seam)" do
    node = render_grid(rows: [ [ { text: "#7", class: "c", html: false,
                                   data: { prefill: "show game #7" } } ] ])
    expect(node.css(".pito-data-grid > span").first["data-prefill"]).to eq("show game #7")
  end

  it "renders info lines with inline code highlighting inside the divider block" do
    node = render_grid(info_lines: [ "run `pito boot` to start" ])
    expect(node.css("code.text-fg").text).to eq("pito boot")
    expect(node.css("span.text-fg-dim").map(&:text).join).to include("run ", " to start")
  end
end
