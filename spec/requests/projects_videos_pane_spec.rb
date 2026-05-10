require "rails_helper"

# Verification sweep (2026-05-10) — focused coverage for the
# `projects/_videos_pane` partial that replaced the retired timelines
# pane on the project show page (Phase 12 realignment).
#
# Existing `projects_spec.rb` asserts the high-level "renders a videos
# pane" shape (3-pane layout, partial included) but does NOT cover:
#   - the heading reads `videos (N)` (count parenthesised, not bare).
#   - the empty-state copy is `no videos yet.` (matches dashboard /
#     videos-index empty state phrasing).
#   - linked videos render with title + privacy + published cells AND
#     link the title to the canonical video show page.
#
# These are filled here so a future regression in the partial is caught
# by request-level coverage.
RSpec.describe "Projects videos pane", type: :request do
  let!(:project) { create(:project) }

  describe "heading count" do
    it "renders `videos (0)` when the project has no linked videos" do
      get project_path(project)
      expect(response.body).to match(/videos\s*\(\s*0\s*\)/)
    end

    it "renders `videos (N)` reflecting the linked count" do
      create(:video, project: project, title: "v1")
      create(:video, project: project, title: "v2")
      get project_path(project)
      expect(response.body).to match(/videos\s*\(\s*2\s*\)/)
    end
  end

  describe "empty-state copy" do
    it "renders `no videos yet.` when there are zero linked videos" do
      get project_path(project)
      expect(response.body).to include("no videos yet.")
    end

    it "does NOT render `no videos yet.` once a video is linked" do
      create(:video, project: project, title: "linked")
      get project_path(project)
      # Multiple panes can mention "videos"; the empty-state string is
      # specific to the videos pane.
      expect(response.body).not_to include("no videos yet.")
    end
  end

  describe "linked-video row content" do
    let!(:video) do
      create(:video,
             project: project,
             title: "Test Video Title",
             privacy_status: :public,
             published_at: Time.zone.local(2026, 4, 15, 12, 0, 0))
    end

    it "renders the video title as a link to the video show page" do
      get project_path(project)
      expect(response.body).to include(%(href="#{video_path(video)}"))
      expect(response.body).to include("Test Video Title")
    end

    it "renders the privacy status cell" do
      get project_path(project)
      expect(response.body).to include("public")
    end

    it "renders the published date in YYYY-MM-DD form" do
      get project_path(project)
      expect(response.body).to include("2026-04-15")
    end

    it "falls back to the youtube_video_id when title is blank" do
      video.update!(title: "")
      get project_path(project)
      expect(response.body).to include(video.youtube_video_id)
    end

    it "renders an em-dash for unpublished videos (published_at nil)" do
      video.update!(privacy_status: :private, published_at: nil)
      get project_path(project)
      # The cell uses `&mdash;` literal in the partial; assertion is on
      # the encoded byte so we don't accidentally match an unrelated dash.
      expect(response.body).to include("&mdash;")
    end
  end

  describe "ordering" do
    let!(:older) { create(:video, project: project, title: "older", published_at: 60.days.ago) }
    let!(:newer) { create(:video, project: project, title: "newer", published_at: 5.days.ago) }
    let!(:unpublished) { create(:video, project: project, title: "unpublished", published_at: nil) }

    it "orders by published_at DESC NULLS LAST" do
      get project_path(project)
      newer_pos = response.body.index("newer")
      older_pos = response.body.index("older")
      unpublished_pos = response.body.index("unpublished")
      expect(newer_pos).to be < older_pos
      expect(older_pos).to be < unpublished_pos
    end
  end

  describe "no [+] add affordance" do
    # The pane has no `[+]` link — videos are sourced from YouTube and
    # association to a project happens via the video edit page, not via
    # an in-pane "add video" form. Lock the absence so a future
    # regression that adds a stray `[+]` is caught.
    it "does not render a [+] bracketed link inside the videos pane" do
      get project_path(project)
      html = Nokogiri::HTML.fragment(response.body)
      videos_pane_h2 = html.css("h2").find { |h| h.text.match?(/videos\s*\(/) }
      expect(videos_pane_h2).not_to be_nil
      pane = videos_pane_h2.ancestors(".pane").first
      expect(pane).not_to be_nil
      add_link = pane.css("a, button").find { |el| el.text.strip.match?(/\A\[\s*\+\s*\]\z/) }
      expect(add_link).to be_nil
    end
  end
end
