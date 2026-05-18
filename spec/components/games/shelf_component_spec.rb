require "rails_helper"

# Wave F rewire — Games::ShelfComponent.
#
# Shared shelf wrapper across `/games` letter shelves, genre sub-
# shelves, and bundles-for-shelf. Renders the section + heading
# + count chip + optional `[see all]` link + horizontal scroll row
# wrapping the caller-provided tiles (via the `content` slot). Also
# exposes a `heading_extras` slot (bundles shelf injects the `[+]`
# create button there).
RSpec.describe Games::ShelfComponent, type: :component do
  # ----------------------------------------------------------------
  # Section wrapper — classes, data-attrs, optional inline style.
  # ----------------------------------------------------------------

  describe "section wrapper" do
    it "always wraps in a <section class=\"shelf\">" do
      render_inline(described_class.new(heading: "A", count: 3))
      expect(page).to have_css("section.shelf")
    end

    it "appends extra_classes to the section class" do
      render_inline(described_class.new(heading: "A", count: 3, extra_classes: "shelf--letter"))
      expect(page).to have_css("section.shelf.shelf--letter")
    end

    it "appends multi-token extra_classes verbatim" do
      render_inline(described_class.new(heading: "A", count: 3, extra_classes: "sub-shelf sub-shelf--genre"))
      expect(page).to have_css("section.shelf.sub-shelf.sub-shelf--genre")
    end

    it "emits data-shelf=<kind> when shelf_kind is provided" do
      render_inline(described_class.new(heading: "A", count: 1, shelf_kind: "letter"))
      expect(page).to have_css("section[data-shelf='letter']")
    end

    it "omits data-shelf when shelf_kind is nil" do
      render_inline(described_class.new(heading: "A", count: 1))
      expect(page).to have_no_css("section[data-shelf]")
    end

    it "wires the steam-shelf Stimulus controller" do
      render_inline(described_class.new(heading: "A", count: 1))
      expect(page).to have_css("section[data-controller='steam-shelf']")
    end

    it "emits arbitrary data-* attributes from the data hash" do
      render_inline(described_class.new(heading: "A", count: 1, data: { letter: "A" }))
      expect(page).to have_css("section[data-letter='A']")
    end

    it "dasherizes underscored data hash keys" do
      render_inline(described_class.new(heading: "G", count: 1, data: { genre_id: 42 }))
      expect(page).to have_css("section[data-genre-id='42']")
    end

    it "omits the section style attribute when no section_style is passed" do
      render_inline(described_class.new(heading: "A", count: 1))
      section = page.find("section.shelf")
      expect(section["style"]).to be_nil.or eq("")
    end

    it "emits the section inline style when section_style is passed" do
      render_inline(described_class.new(heading: "A", count: 1, section_style: "margin-top: 12px"))
      section = page.find("section.shelf")
      expect(section["style"]).to include("margin-top: 12px")
    end
  end

  # ----------------------------------------------------------------
  # Heading — h2 by default, h3 when heading_level: :h3.
  # ----------------------------------------------------------------

  describe "heading" do
    it "renders as <h2> by default" do
      render_inline(described_class.new(heading: "A", count: 5))
      expect(page).to have_css("section.shelf .dot-list h2", text: /\AA/)
    end

    it "renders as <h3> when heading_level: :h3" do
      render_inline(described_class.new(heading: "Action", count: 5, heading_level: :h3))
      expect(page).to have_css("section.shelf .dot-list h3", text: /\AAction/)
    end

    it "renders the heading text verbatim" do
      render_inline(described_class.new(heading: "Z", count: 1))
      expect(page).to have_text("Z")
    end

    it "always wraps heading + count in a .dot-list container" do
      render_inline(described_class.new(heading: "A", count: 1))
      expect(page).to have_css(".dot-list")
    end

    it "applies the heading_margin to the dot-list wrapper" do
      render_inline(described_class.new(heading: "A", count: 1, heading_margin: "4px"))
      dot_list = page.find(".dot-list")
      expect(dot_list["style"]).to include("margin-bottom: 4px")
    end

    it "defaults heading_margin to 6px" do
      render_inline(described_class.new(heading: "A", count: 1))
      dot_list = page.find(".dot-list")
      expect(dot_list["style"]).to include("margin-bottom: 6px")
    end

    it "applies heading_style verbatim when passed" do
      render_inline(described_class.new(heading: "A", count: 1, heading_style: "font-size: 13px"))
      heading = page.find("h2")
      expect(heading["style"]).to include("font-size: 13px")
    end

    it "always zeros heading margin via inline style" do
      render_inline(described_class.new(heading: "A", count: 1))
      heading = page.find("h2")
      expect(heading["style"]).to include("margin: 0")
    end
  end

  # ----------------------------------------------------------------
  # Count chip — renders via StatusBadgeComponent when present.
  # ----------------------------------------------------------------

  describe "count chip" do
    it "renders a status-badge inside the heading when count is provided" do
      render_inline(described_class.new(heading: "A", count: 7))
      expect(page).to have_css("h2 .status-badge", text: "7")
    end

    it "renders the count as a string" do
      render_inline(described_class.new(heading: "A", count: 42))
      expect(page).to have_css(".status-badge", text: "42")
    end

    it "still renders a 0 count chip when count is explicitly 0" do
      render_inline(described_class.new(heading: "A", count: 0))
      expect(page).to have_css(".status-badge", text: "0")
    end

    it "does NOT render the count chip when count is nil" do
      render_inline(described_class.new(heading: "A"))
      expect(page).to have_no_css(".status-badge")
    end

    it "does NOT render the count chip when show_count: false" do
      render_inline(described_class.new(heading: "A", count: 5, show_count: false))
      expect(page).to have_no_css(".status-badge")
    end
  end

  # ----------------------------------------------------------------
  # `[see all]` link — only renders when more_href provided.
  # ----------------------------------------------------------------

  describe "[see all] link" do
    it "renders inside the heading when more_href is provided" do
      render_inline(described_class.new(heading: "A", count: 1,
                                        more_href: "/games?filters=action"))
      expect(page).to have_css(".dot-list a", text: /see all/i)
    end

    it "links the [see all] anchor to more_href" do
      render_inline(described_class.new(heading: "A", count: 1,
                                        more_href: "/games?filters=action"))
      link = page.find(".dot-list a", text: /see all/i)
      expect(link["href"]).to eq("/games?filters=action")
    end

    it "does NOT render the [see all] link when more_href is nil" do
      render_inline(described_class.new(heading: "A", count: 1))
      expect(page).to have_no_css(".dot-list a", text: /see all/i)
    end
  end

  # ----------------------------------------------------------------
  # Row — horizontal scroll wrapper, gap, optional alignment.
  # ----------------------------------------------------------------

  describe "row wrapper" do
    it "always renders a .shelf-row container" do
      render_inline(described_class.new(heading: "A", count: 1))
      expect(page).to have_css(".shelf-row")
    end

    it "appends row_classes to the row class" do
      render_inline(described_class.new(heading: "A", count: 1, row_classes: "letter-shelf-row"))
      expect(page).to have_css(".shelf-row.letter-shelf-row")
    end

    it "wires the steam-shelf row target" do
      render_inline(described_class.new(heading: "A", count: 1))
      expect(page).to have_css(".shelf-row[data-steam-shelf-target='row']")
    end

    it "renders the row as flex with overflow-x: auto (horizontal scroll)" do
      render_inline(described_class.new(heading: "A", count: 1))
      row = page.find(".shelf-row")
      expect(row["style"]).to include("display: flex")
      expect(row["style"]).to include("overflow-x: auto")
    end

    it "defaults the row gap to 6px" do
      render_inline(described_class.new(heading: "A", count: 1))
      row = page.find(".shelf-row")
      expect(row["style"]).to include("gap: 6px")
    end

    it "honors a custom row_gap" do
      render_inline(described_class.new(heading: "A", count: 1, row_gap: "12px"))
      row = page.find(".shelf-row")
      expect(row["style"]).to include("gap: 12px")
    end

    it "emits align-items only when row_align is provided" do
      render_inline(described_class.new(heading: "A", count: 1, row_align: "flex-start"))
      row = page.find(".shelf-row")
      expect(row["style"]).to include("align-items: flex-start")
    end

    it "omits align-items when row_align is nil" do
      render_inline(described_class.new(heading: "A", count: 1))
      row = page.find(".shelf-row")
      expect(row["style"]).not_to include("align-items")
    end

    it "always pads the row bottom for the scrollbar gutter" do
      render_inline(described_class.new(heading: "A", count: 1))
      row = page.find(".shelf-row")
      expect(row["style"]).to include("padding-bottom: 6px")
    end
  end

  # ----------------------------------------------------------------
  # Content slot — caller-provided tiles land inside .shelf-row.
  # ----------------------------------------------------------------

  describe "content slot" do
    it "yields caller-provided tile markup into the .shelf-row" do
      render_inline(described_class.new(heading: "A", count: 1)) do
        '<div class="tile" data-tile="x">tile-1</div>'.html_safe
      end
      expect(page).to have_css(".shelf-row .tile[data-tile='x']", text: "tile-1")
    end

    it "accepts multiple tiles in the content block" do
      render_inline(described_class.new(heading: "A", count: 2)) do
        '<div class="tile">a</div><div class="tile">b</div>'.html_safe
      end
      expect(page).to have_css(".shelf-row .tile", count: 2)
    end
  end

  # ----------------------------------------------------------------
  # heading_extras slot — additional heading-level markup, rendered
  # AFTER the count chip and AFTER `[see all]`.
  # ----------------------------------------------------------------

  describe "heading_extras slot" do
    it "renders the heading_extras content inside the .dot-list" do
      render_inline(described_class.new(heading: "A", count: 1)) do |component|
        component.with_heading_extras { '<a class="bracketed" href="/x">[+]</a>'.html_safe }
      end
      expect(page).to have_css(".dot-list a.bracketed[href='/x']", text: "[+]")
    end

    it "does NOT render any heading_extras wrapper when the slot is unused" do
      render_inline(described_class.new(heading: "A", count: 1))
      # The .dot-list should hold only the heading; assert no anchor inside.
      expect(page).to have_no_css(".dot-list a")
    end
  end

  # ----------------------------------------------------------------
  # Hard rules — no JS confirm or destructive scripting.
  # ----------------------------------------------------------------

  describe "flaw: no JS confirm" do
    it "never emits data-turbo-confirm" do
      render_inline(described_class.new(heading: "A", count: 1, more_href: "/x"))
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits window.confirm or alert" do
      render_inline(described_class.new(heading: "A", count: 1))
      html = page.native.to_html
      expect(html).not_to include("window.confirm")
      expect(html).not_to include("alert(")
    end
  end
end
