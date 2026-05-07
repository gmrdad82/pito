# Phase 4 §3.1, §4 — workspace shell. References zero-or-more Games and
# Collections via the polymorphic `project_references` join.
class Project < ApplicationRecord
  include BelongsToTenant

  has_many :project_references, dependent: :destroy
  has_many :games,
           through: :project_references,
           source: :referenceable,
           source_type: "Game"
  has_many :collections,
           through: :project_references,
           source: :referenceable,
           source_type: "Collection"

  has_many :footages, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_many :timelines, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }

  # Phase 4 §2 "Default-create everywhere" — DB default is "Untitled project";
  # this keeps Project.new (no name) rendering the same default in spec
  # introspection without going through the DB.
  attribute :name, :string, default: "Untitled project"

  # Phase B (2026-05-04) — after every Note has been destroyed (and each
  # one's on-disk file removed via Note#before_destroy), nuke the now-empty
  # per-project notes directory. Runs after the DB transaction commits so
  # we never orphan a directory deletion if the destroy is rolled back.
  after_destroy_commit :delete_notes_directory

  private

  def delete_notes_directory
    NotesFilesystem.delete_project_dir(self)
  rescue StandardError => e
    Rails.logger.warn("Project##{id} notes dir cleanup failed: #{e.class}: #{e.message}")
  end
end
