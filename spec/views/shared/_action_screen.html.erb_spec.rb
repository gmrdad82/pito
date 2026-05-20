require "rails_helper"

# Beta 4 — Phase F3-DEEP-B (2026-05-20). Shared action-screen footer.
#
# The partial owns the [confirm] / [cancel] bracketed-link bar at the
# foot of every action-confirmation page (`DeletionsController#new`,
# `SyncsController#new`, anything else routed through the
# `Confirmable` concern). Before the F3-DEEP-B revamp the row rendered
# browser-default `<button>` styling; the revamp swaps to:
#
#   [confirm] — bracketed-link button (link-color by default, pink
#               with `.text-danger` when `destructive: true`)
#   [cancel]  — `BracketedMutedLinkComponent` (muted)
#
# The label callers pass is bare (`"delete"`, `"sync"`, etc.); the
# partial wraps it in `[<span class="bl">…</span>]` so legacy callers
# that already pass `"[wrapped]"` keep working — the partial strips a
# single set of surrounding brackets before re-wrapping.
RSpec.describe "shared/_action_screen.html.erb", type: :view do
  let(:cancel_path) { "/games" }
  let(:form_url) { "/deletions/games/42" }

  describe "non-destructive default" do
    before do
      render partial: "shared/action_screen", locals: {
        submit_label: "sync",
        cancel_path: cancel_path,
        form_url: form_url
      }
    end

    it "renders the form pointed at the supplied URL" do
      expect(rendered).to include(%(action="#{form_url}"))
    end

    it "renders the [confirm] submit button with the bracketed class and the .bl label span" do
      expect(rendered).to have_css(
        'button[type="submit"].bracketed span.bl', text: "sync"
      )
    end

    it "does NOT apply the `.text-danger` modifier when destructive is omitted" do
      expect(rendered).not_to match(
        /button[^>]*class="[^"]*bracketed[^"]*text-danger/
      )
    end

    it "renders the [cancel] muted bracketed link pointed at the cancel path" do
      # `BracketedMutedLinkComponent` emits an `<a class="bracketed
      # bracketed-muted-link">` with the `.bl` label span.
      expect(rendered).to have_css(
        'a.bracketed.bracketed-muted-link[href="/games"] span.bl', text: "cancel"
      )
    end

    it "stacks the [confirm] / [cancel] pair inside a `.dot-list` row" do
      # Layout primitive — the row renders inline with a middle-dot
      # separator, same as the rest of the bracketed-link bars across
      # the site.
      expect(rendered).to have_css(
        ".action-screen-footer .dot-list button.bracketed[type='submit']"
      )
      expect(rendered).to have_css(
        ".action-screen-footer .dot-list a.bracketed-muted-link"
      )
    end
  end

  describe "destructive variant" do
    before do
      render partial: "shared/action_screen", locals: {
        submit_label: "delete",
        cancel_path: cancel_path,
        form_url: form_url,
        destructive: true
      }
    end

    it "stamps `.text-danger` on the [confirm] button class list" do
      # The destructive path mirrors the project rule that red is
      # reserved for destructive actions — the button picks up the
      # `--color-danger` foreground via the `.text-danger` modifier.
      expect(rendered).to match(
        /button[^>]*class="[^"]*bracketed[^"]*action-screen-submit[^"]*text-danger/
      )
    end

    it "still renders the [cancel] link as muted (NOT danger)" do
      # The danger styling is reserved for the destructive action;
      # cancel stays muted regardless.
      expect(rendered).not_to match(
        /bracketed-muted-link[^>]*text-danger/
      )
    end
  end

  describe "legacy `[wrapped]` label compatibility" do
    before do
      render partial: "shared/action_screen", locals: {
        submit_label: "[delete]",
        cancel_path: cancel_path,
        form_url: form_url,
        destructive: true
      }
    end

    it "strips the outer brackets so the label renders cleanly inside the partial's own brackets" do
      # The clean label sits inside the `<span class="bl">` and the
      # partial supplies the surrounding `[` / `]`. A literal
      # `[[delete]]` double-wrap would indicate the strip path
      # regressed.
      expect(rendered).to have_css(
        'button[type="submit"].bracketed span.bl', text: "delete"
      )
      expect(rendered).not_to include(">[delete]<")
    end
  end

  describe "keyboard confirmation wiring (y / Esc)" do
    before do
      render partial: "shared/action_screen", locals: {
        submit_label: "delete",
        cancel_path: cancel_path,
        form_url: form_url,
        destructive: true
      }
    end

    it "tags the form with data-keyboard-confirmation=\"true\" so `y` triggers submit" do
      expect(rendered).to match(/<form[^>]*data-keyboard-confirmation="true"/)
    end

    it "tags the cancel link with data-keyboard-confirmation-cancel=\"true\" so Esc closes" do
      expect(rendered).to match(
        /a[^>]*data-keyboard-confirmation-cancel="true"/
      )
    end

    it "renders the form with data-turbo=\"false\" so the submission goes full-page" do
      expect(rendered).to match(/<form[^>]*data-turbo="false"/)
    end
  end

  describe "explicit form method override" do
    it "honours `form_method: :delete` so the form posts the DELETE verb" do
      render partial: "shared/action_screen", locals: {
        submit_label: "delete",
        cancel_path: cancel_path,
        form_url: form_url,
        form_method: :delete
      }
      expect(rendered).to match(/name="_method"[^>]*value="delete"/)
    end

    it "defaults to POST when form_method is omitted" do
      render partial: "shared/action_screen", locals: {
        submit_label: "sync",
        cancel_path: cancel_path,
        form_url: form_url
      }
      # Rails `form_with method: :post` does NOT emit a `_method`
      # override input — POST is the wire verb.
      expect(rendered).not_to match(/name="_method"/)
    end
  end

  describe "no forbidden JS confirm hooks" do
    it "does NOT render data-turbo-confirm anywhere in the partial" do
      render partial: "shared/action_screen", locals: {
        submit_label: "delete",
        cancel_path: cancel_path,
        form_url: form_url,
        destructive: true
      }
      expect(rendered).not_to include("data-turbo-confirm")
    end
  end
end
