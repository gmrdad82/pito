require "rails_helper"

# Hjkl-on-every-surface helper (2026-05-10).
#
# `keyboard_detail_nav_attrs` computes prev / next sibling URLs for a
# detail (show) page so the global keyboard controller's `h` / `l`
# bindings can navigate via Turbo. Sibling order is the model's natural
# id-ascending order — stable, decoupled from per-page URL sort params.
#
# `keyboard_detail_nav_data_attributes` is the safe-HTML renderer
# templates interpolate inside a `<div ...>` tag.
RSpec.describe KeyboardNavigationHelper, type: :helper do
  describe "#keyboard_detail_nav_attrs" do
    context "with three siblings in id order" do
      let!(:a) { create(:project, name: "Alpha") }
      let!(:b) { create(:project, name: "Bravo") }
      let!(:c) { create(:project, name: "Charlie") }

      it "returns both prev and next URLs for the middle record" do
        attrs = helper.keyboard_detail_nav_attrs(
          b, scope: Project, path_helper: ->(p) { "/projects/#{p.to_param}" }
        )
        expect(attrs).to eq(
          "data-keyboard-detail-prev-url" => "/projects/#{a.to_param}",
          "data-keyboard-detail-next-url" => "/projects/#{c.to_param}"
        )
      end

      it "omits the prev URL for the first record" do
        attrs = helper.keyboard_detail_nav_attrs(
          a, scope: Project, path_helper: ->(p) { "/projects/#{p.to_param}" }
        )
        expect(attrs).not_to have_key("data-keyboard-detail-prev-url")
        expect(attrs).to have_key("data-keyboard-detail-next-url")
      end

      it "omits the next URL for the last record" do
        attrs = helper.keyboard_detail_nav_attrs(
          c, scope: Project, path_helper: ->(p) { "/projects/#{p.to_param}" }
        )
        expect(attrs).to have_key("data-keyboard-detail-prev-url")
        expect(attrs).not_to have_key("data-keyboard-detail-next-url")
      end
    end

    context "with a single record" do
      let!(:solo) { create(:project, name: "Solo") }

      it "returns an empty hash (no sibling on either side)" do
        attrs = helper.keyboard_detail_nav_attrs(
          solo, scope: Project, path_helper: ->(p) { "/projects/#{p.to_param}" }
        )
        expect(attrs).to eq({})
      end
    end

    context "with a parent-scoped relation" do
      let!(:project)    { create(:project) }
      let!(:other_proj) { create(:project) }
      let!(:note_a)     { create(:note, project: project, path: "a.md") }
      let!(:note_b)     { create(:note, project: project, path: "b.md") }
      # A note in another project — must NOT appear as a sibling.
      let!(:note_other) { create(:note, project: other_proj, path: "other.md") }

      it "limits siblings to the parent association" do
        attrs = helper.keyboard_detail_nav_attrs(
          note_a, scope: project.notes, path_helper: ->(n) { "/notes/#{n.to_param}" }
        )
        expect(attrs).to eq(
          "data-keyboard-detail-next-url" => "/notes/#{note_b.to_param}"
        )
      end
    end

    context "with a nil record" do
      it "returns an empty hash" do
        attrs = helper.keyboard_detail_nav_attrs(
          nil, scope: Project, path_helper: ->(_) { "/anywhere" }
        )
        expect(attrs).to eq({})
      end
    end

    context "with a relation that already carries an ORDER BY" do
      let!(:a) { create(:project, name: "Alpha") }
      let!(:b) { create(:project, name: "Bravo") }
      let!(:c) { create(:project, name: "Charlie") }

      it "reorders by id so siblings are deterministic regardless of input scope order" do
        # Caller might pass a relation already ordered by name desc; the
        # helper must override that and order by id ascending so
        # `h` / `l` always step in the same direction.
        scope = Project.order(name: :desc)
        attrs = helper.keyboard_detail_nav_attrs(
          b, scope: scope, path_helper: ->(p) { "/projects/#{p.to_param}" }
        )
        expect(attrs["data-keyboard-detail-prev-url"]).to eq("/projects/#{a.to_param}")
        expect(attrs["data-keyboard-detail-next-url"]).to eq("/projects/#{c.to_param}")
      end
    end
  end

  describe "#keyboard_detail_nav_data_attributes" do
    let!(:a) { create(:project, name: "Alpha") }
    let!(:b) { create(:project, name: "Bravo") }
    let!(:c) { create(:project, name: "Charlie") }

    it "renders both URLs as safe HTML attribute pairs" do
      html = helper.keyboard_detail_nav_data_attributes(
        b, scope: Project, path_helper: ->(p) { "/projects/#{p.to_param}" }
      )
      expect(html).to be_html_safe
      expect(html).to include(%(data-keyboard-detail-prev-url="/projects/#{a.to_param}"))
      expect(html).to include(%(data-keyboard-detail-next-url="/projects/#{c.to_param}"))
    end

    it "returns an empty html_safe string when the record has no siblings" do
      Project.where.not(id: a.id).delete_all
      html = helper.keyboard_detail_nav_data_attributes(
        a, scope: Project, path_helper: ->(p) { "/projects/#{p.to_param}" }
      )
      expect(html).to eq("")
      expect(html).to be_html_safe
    end

    it "escapes URL characters so injected markup is neutralized" do
      # The path helper is server-rendered so this is defense in depth,
      # but we still want to confirm `&` / quote / `<` characters survive
      # the html_safe wrapping intact (escaped, not interpreted).
      html = helper.keyboard_detail_nav_data_attributes(
        b, scope: Project, path_helper: ->(_) { %(/projects/"><script>alert(1)</script>) }
      )
      expect(html).not_to include("<script>")
      expect(html).to include("&lt;script&gt;").or include("&quot;")
    end
  end
end
