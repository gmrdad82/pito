require "rails_helper"

# 2026-05-11 — modal-frame ID convention regression guard.
#
# Convention: every turbo-frame that hosts a modal surface uses the
# snake_case suffix `_modal_frame`. The reviewer flagged inconsistent
# naming after a wave of merges (`calendar_entry_details_frame`,
# `pre-publish-modal-frame`) so this spec pins the renames AND blocks
# the prior shapes from returning by name.
#
# Scope: pure source-tree assertions. No browser, no JS. Reads the
# views + JS controllers via Rails.root and pattern-matches.
RSpec.describe "Modal frame ID convention (`<scope>_modal_frame`)", type: :system do
  before { driven_by(:rack_test) }

  let(:views_root) { Rails.root.join("app/views") }
  let(:js_root) { Rails.root.join("app/javascript/controllers") }

  def read_all(root, glob)
    Pathname.glob(root.join(glob)).map { |p| p.read }.join("\n")
  end

  it "no view references the legacy `calendar_entry_details_frame` ID" do
    body = read_all(views_root, "**/*.erb")
    expect(body).not_to include("calendar_entry_details_frame")
  end

  it "no view references the legacy `pre-publish-modal-frame` kebab-case ID" do
    body = read_all(views_root, "**/*.erb")
    expect(body).not_to include("pre-publish-modal-frame")
  end

  it "the calendar entry modal view declares `calendar_entry_modal_frame`" do
    body = views_root.join("calendar/_entry_modal.html.erb").read
    expect(body).to include("calendar_entry_modal_frame")
  end

  it "the calendar entry details_pane view declares `calendar_entry_modal_frame`" do
    body = views_root.join("calendar/entries/details_pane.html.erb").read
    expect(body).to include("calendar_entry_modal_frame")
  end

  it "the pre-publish modal partial declares `pre_publish_modal_frame`" do
    body = views_root.join("videos/_pre_publish_modal.html.erb").read
    expect(body).to include("pre_publish_modal_frame")
  end

  it "the video form trigger targets `pre_publish_modal_frame`" do
    body = views_root.join("videos/_form.html.erb").read
    expect(body).to include("pre_publish_modal_frame")
  end

  # Convention guard: every modal frame ID in the codebase ends with
  # `_modal_frame` (snake_case). We scan the rendered turbo_frame_tag
  # invocations under the views tree; anything that does not match the
  # convention surfaces here.
  it "every `turbo_frame_tag \"<x>\"` declaration in the views uses the `_modal_frame` suffix when the scope is a modal" do
    body = read_all(views_root, "**/*.erb")
    modal_frame_ids = body.scan(/turbo_frame_tag\s+"([a-z_]+modal[a-z_]*)"/).flatten.uniq
    bad = modal_frame_ids.reject { |id| id.end_with?("_modal_frame") }
    expect(bad).to be_empty, "non-conforming modal frame IDs: #{bad.inspect}"
  end
end
