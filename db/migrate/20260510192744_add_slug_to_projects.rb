# Phase 20 — friendly URLs.
#
# Adds a `slug` column to projects, backfills from `name`, then enforces
# NOT NULL + a unique index. Slugs are generated via the same
# `Babosa::Identifier` rules friendly_id uses at runtime so backfilled
# rows match the gem's normalization (lowercase, transliterated, hyphen-
# separated, truncated at 80 chars on a word boundary).
class AddSlugToProjects < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :slug, :string

    # Backfill. Use a thin model class so we don't drag the live `Project`
    # (with its callbacks, validations, has_many cascades) into the
    # migration.
    project_klass = Class.new(ActiveRecord::Base) { self.table_name = "projects" }
    project_klass.reset_column_information
    project_klass.find_each do |row|
      candidate = Pito::SlugBuilder.build(row.name.presence || "project-#{row.id}", limit: 80)
      candidate = "project-#{row.id}" if candidate.blank?
      slug = unique_slug(candidate, project_klass, row.id)
      row.update_columns(slug: slug)
    end

    change_column_null :projects, :slug, false
    add_index :projects, :slug, unique: true
  end

  def down
    remove_index :projects, :slug
    remove_column :projects, :slug
  end

  private

  # Append `-2`, `-3`, ... when the candidate collides. Mirrors
  # friendly_id's default candidate-resolution pattern.
  def unique_slug(candidate, klass, current_id)
    base = candidate
    suffix = 1
    loop do
      try = suffix == 1 ? base : "#{base}-#{suffix}"
      taken = klass.where(slug: try).where.not(id: current_id).exists?
      return try unless taken
      suffix += 1
    end
  end
end
