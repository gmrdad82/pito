require "rails_helper"

# Phase 27 — 01d. Display mode switcher partial.
#
# The switcher renders three `button_to` forms PATCHing
# `/users/games_preferences` — one per display mode. The active mode
# carries the `active` CSS class. Pure form submit, no JS.
RSpec.describe "games/_display_mode_switcher.html.erb", type: :view do
  def render_switcher(active_mode:)
    render partial: "games/display_mode_switcher", locals: { active_mode: active_mode }
  end

  describe "rendered structure (happy path)" do
    it "renders three button_to forms, one per mode" do
      render_switcher(active_mode: :grid)

      expect(rendered).to include('action="/users/games_preferences"')
      # PATCH method is encoded via Rails' hidden `_method` field.
      expect(rendered).to include('name="_method" value="patch"')
      # All three modes carry their own button + hidden `mode` input.
      expect(rendered).to include('value="grid"')
      expect(rendered).to include('value="list"')
      expect(rendered).to include('value="shelves_by_letter"')
    end

    it "labels the three buttons grid / list / shelves" do
      render_switcher(active_mode: :grid)
      expect(rendered).to include("[<span class=\"bl\">grid</span>]")
      expect(rendered).to include("[<span class=\"bl\">list</span>]")
      expect(rendered).to include("[<span class=\"bl\">shelves</span>]")
    end

    it "stamps the wrapper with data-active-mode for downstream styling" do
      render_switcher(active_mode: :list)
      expect(rendered).to include('data-active-mode="list"')
    end
  end

  describe "active class" do
    it "marks grid active when active_mode == :grid" do
      render_switcher(active_mode: :grid)
      # The `bracketed active` class belongs to the grid form only.
      expect(rendered).to match(/class="bracketed active"[^>]*>\s*\n?\s*\[<span class="bl">grid<\/span>\]/m)
      expect(rendered).not_to match(/class="bracketed active"[^>]*>\s*\n?\s*\[<span class="bl">list<\/span>\]/m)
    end

    it "marks list active when active_mode == :list" do
      render_switcher(active_mode: :list)
      expect(rendered).to match(/class="bracketed active"[^>]*>\s*\n?\s*\[<span class="bl">list<\/span>\]/m)
    end

    it "marks shelves_by_letter active when active_mode == :shelves_by_letter" do
      render_switcher(active_mode: :shelves_by_letter)
      expect(rendered).to match(/class="bracketed active"[^>]*>\s*\n?\s*\[<span class="bl">shelves<\/span>\]/m)
    end

    it "accepts a String active_mode equivalently to a Symbol" do
      render_switcher(active_mode: "list")
      expect(rendered).to match(/class="bracketed active"[^>]*>\s*\n?\s*\[<span class="bl">list<\/span>\]/m)
    end
  end

  describe "design-rule guards (CLAUDE.md hard rules)" do
    it "does NOT emit JS confirm / alert / prompt anywhere" do
      render_switcher(active_mode: :grid)
      expect(rendered).not_to include("window.confirm")
      expect(rendered).not_to include("data-turbo-confirm")
      expect(rendered).not_to include("alert(")
    end

    it "does NOT emit the destructive `text-danger` class (no red on switcher)" do
      render_switcher(active_mode: :grid)
      expect(rendered).not_to include("text-danger")
    end

    it "renders as a real form (not an anchor)" do
      render_switcher(active_mode: :grid)
      # Three forms, three submit buttons. No `<a href`.
      expect(rendered.scan(/<form\b/).length).to eq(3)
    end
  end
end
