# Phase 4 §3.1, §4 — workspace shell. References zero-or-more Games and
# Collections via the polymorphic `project_references` join.
class Project < ApplicationRecord
  # Phase 20 — friendly URLs. Project URLs use a name-derived slug. The
  # `:history` module redirects old slugs after a rename. Backfilled by
  # `db/migrate/20260510192744_add_slug_to_projects.rb`. `:finders` lets
  # `Project.friendly.find(slug_or_id)` accept either input. The `name` →
  # slug pipeline routes through `Pito::SlugBuilder` so backfilled slugs
  # and runtime-generated slugs share the same normalization rules.
  extend FriendlyId
  friendly_id :slug_candidates, use: %i[slugged history finders]

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

  # Phase 12 — direct nullable Project ↔ Video link (Resolved decision
  # Q1). On Project deletion, Videos survive with `project_id = NULL`
  # so the YouTube-side data is preserved when the local workspace
  # bundle that organized them goes away.
  has_many :videos, dependent: :nullify

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

  # Phase 20 — friendly URLs. Per-resource cap; the locked default is
  # 80 chars (`docs/plans/beta/20-friendly-urls/...` master decision #6).
  def slug_limit
    80
  end

  # Candidates fed to friendly_id's slug generator. The first non-blank
  # candidate that isn't already taken wins; ties resolve via the gem's
  # default `-2`, `-3`, ... suffix.
  def slug_candidates
    [
      normalized_name_slug,
      [ normalized_name_slug, id ].compact.reject(&:blank?).join("-"),
      "project-#{id}"
    ]
  end

  # Trigger slug regeneration on rename. Without this, friendly_id keeps
  # the original slug even when `name` changes (the gem only generates a
  # slug when the column is blank).
  def should_generate_new_friendly_id?
    will_save_change_to_name? || super
  end

  # Override the gem's normalization so renames + backfill share
  # `Pito::SlugBuilder` (transliteration + 80-char cap).
  def normalize_friendly_id(value)
    Pito::SlugBuilder.build(value.to_s, limit: slug_limit).presence ||
      "project-#{id || SecureRandom.hex(4)}"
  end

  private

  def normalized_name_slug
    Pito::SlugBuilder.build(name.to_s, limit: slug_limit)
  end

  def delete_notes_directory
    NotesFilesystem.delete_project_dir(self)
  rescue StandardError => e
    Rails.logger.warn("Project##{id} notes dir cleanup failed: #{e.class}: #{e.message}")
  end
end
