require "rails_helper"

RSpec.describe Tui::CheckboxComponent, type: :component do
  describe "glyph rendering" do
    it "renders the unchecked state as `[ ]`" do
      render_inline(described_class.new(checked: false))

      expect(page).to have_css(".tui-checkbox__box", text: "[ ]")
    end

    it "renders the checked state as `[x]`" do
      render_inline(described_class.new(checked: true))

      expect(page).to have_css(".tui-checkbox__box", text: "[x]")
    end

    it "defaults to unchecked when `checked:` not passed" do
      render_inline(described_class.new)

      expect(page).to have_css(".tui-checkbox__box", text: "[ ]")
    end

    it "coerces truthy non-boolean `checked:` values" do
      render_inline(described_class.new(checked: "yes"))

      expect(page).to have_css(".tui-checkbox__box", text: "[x]")
    end
  end

  describe "render-mode selection" do
    context "when `href:` is given" do
      it "renders as an `<a>` element pointing at the href" do
        render_inline(described_class.new(href: "/things?foo=yes"))

        expect(page).to have_css('a.tui-checkbox[href="/things?foo=yes"]')
      end

      it "does not render a hidden input or a checkbox input" do
        render_inline(described_class.new(href: "/things"))

        expect(page).to have_no_css('input[type="hidden"]')
        expect(page).to have_no_css('input[type="checkbox"]')
      end

      it "wins over `name:` when both are given (link mode preferred)" do
        render_inline(described_class.new(href: "/things", name: "ignored"))

        expect(page).to have_css("a.tui-checkbox")
        expect(page).to have_no_css("label.tui-checkbox")
      end
    end

    context "when `name:` is given (and no href)" do
      it "renders as a `<label>` wrapping a hidden input + a checkbox" do
        render_inline(described_class.new(name: "all"))

        expect(page).to have_css("label.tui-checkbox")
        expect(page).to have_css('label.tui-checkbox input[type="hidden"][name="all"]', visible: :all)
        expect(page).to have_css('label.tui-checkbox input[type="checkbox"][name="all"]', visible: :all)
      end

      # FB-97 — form variant adds .tui-checkbox--form so the CSS
      # `:has(input:checked)` selector can drive the glyph from input state
      # (keyboard Space + JS .click() both update the visible glyph without
      # a server re-render).
      it "tags the label with `.tui-checkbox--form` for the CSS-driven glyph" do
        render_inline(described_class.new(name: "all"))

        expect(page).to have_css("label.tui-checkbox.tui-checkbox--form")
      end

      it "renders the glyph box as an empty span (glyph injected via CSS ::before)" do
        render_inline(described_class.new(name: "all", checked: true))

        box = page.find("label.tui-checkbox--form .tui-checkbox__box")
        expect(box.text).to eq("")
      end

      it "hidden input value is `no` per pito's yes/no boolean convention" do
        render_inline(described_class.new(name: "all"))

        hidden = page.find('input[type="hidden"][name="all"]', visible: :all)
        expect(hidden[:value]).to eq("no")
      end

      it "checkbox input value defaults to `yes`" do
        render_inline(described_class.new(name: "all"))

        checkbox = page.find('input[type="checkbox"][name="all"]', visible: :all)
        expect(checkbox[:value]).to eq("yes")
      end

      it "honors a custom `value:` for the checkbox input" do
        render_inline(described_class.new(name: "all", value: "subscribe"))

        checkbox = page.find('input[type="checkbox"][name="all"]', visible: :all)
        expect(checkbox[:value]).to eq("subscribe")
      end

      it "renders the checkbox as checked when `checked: true`" do
        render_inline(described_class.new(name: "all", checked: true))

        expect(page).to have_css('input[type="checkbox"][checked]', visible: :all)
      end

      it "renders the checkbox unchecked by default" do
        render_inline(described_class.new(name: "all"))

        expect(page).to have_no_css('input[type="checkbox"][checked]', visible: :all)
      end
    end

    context "when neither href nor name is given" do
      it "renders as a static `<span>`" do
        render_inline(described_class.new)

        expect(page).to have_css("span.tui-checkbox")
        expect(page).to have_no_css("a.tui-checkbox")
        expect(page).to have_no_css("label.tui-checkbox")
      end

      it "does not render any form inputs" do
        render_inline(described_class.new(checked: true))

        expect(page).to have_no_css('input[type="hidden"]')
        expect(page).to have_no_css('input[type="checkbox"]')
      end
    end
  end

  describe "labels" do
    it "renders the label with a leading space after the box" do
      render_inline(described_class.new(label: "all"))

      expect(page).to have_css(".tui-checkbox__label", text: "all")
    end

    it "omits the label span entirely when label is nil" do
      render_inline(described_class.new(label: nil))

      expect(page).to have_no_css(".tui-checkbox__label")
    end

    it "renders the label inside the link variant" do
      render_inline(described_class.new(label: "subscribe", href: "/things"))

      expect(page).to have_css("a.tui-checkbox .tui-checkbox__label", text: "subscribe")
    end

    it "renders the label inside the form variant" do
      render_inline(described_class.new(label: "subscribe", name: "sub"))

      expect(page).to have_css("label.tui-checkbox .tui-checkbox__label", text: "subscribe")
    end
  end

  describe "checked modifier class" do
    it "adds `.tui-checkbox--checked` when `checked: true`" do
      render_inline(described_class.new(checked: true))

      expect(page).to have_css(".tui-checkbox.tui-checkbox--checked")
    end

    it "omits `.tui-checkbox--checked` when `checked: false`" do
      render_inline(described_class.new(checked: false))

      expect(page).to have_no_css(".tui-checkbox--checked")
    end

    it "applies the checked class in link mode too" do
      render_inline(described_class.new(href: "/things", checked: true))

      expect(page).to have_css("a.tui-checkbox.tui-checkbox--checked")
    end

    it "applies the checked class in form mode too" do
      render_inline(described_class.new(name: "all", checked: true))

      expect(page).to have_css("label.tui-checkbox.tui-checkbox--checked")
    end
  end

  describe "mode predicates" do
    it "renders_as_link? is true only when href is set" do
      expect(described_class.new(href: "/x").renders_as_link?).to be true
      expect(described_class.new(name: "x").renders_as_link?).to be false
      expect(described_class.new.renders_as_link?).to be false
    end

    it "renders_as_form_input? is true only when name is set without href" do
      expect(described_class.new(name: "x").renders_as_form_input?).to be true
      expect(described_class.new(href: "/x", name: "x").renders_as_form_input?).to be false
      expect(described_class.new.renders_as_form_input?).to be false
    end
  end
end
