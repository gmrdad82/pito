require "rails_helper"

# Phase 20 — friendly URLs. Note keeps `path` as its natural identifier;
# the route uses a `*path` glob so slash-bearing paths reach the
# controller intact.
RSpec.describe Note, type: :model do
  describe "#to_param" do
    it "returns the path verbatim" do
      project = create(:project)
      note = project.notes.create!(
        path: "subdir/example-note.md",
        title: "Example",
        last_modified_at: Time.current
      )
      expect(note.to_param).to eq("subdir/example-note.md")
    end
  end

  describe "Note.find_by!(path:)" do
    it "resolves to the right record" do
      project = create(:project)
      note = project.notes.create!(
        path: "deep/nested/note.md",
        title: "Deep",
        last_modified_at: Time.current
      )
      expect(Note.find_by!(path: "deep/nested/note.md")).to eq(note)
    end

    it "raises RecordNotFound on a miss" do
      expect { Note.find_by!(path: "missing.md") }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
