# Phase 20 — friendly URLs. MilestoneRule slug column + backfill.
class AddSlugToMilestoneRules < ActiveRecord::Migration[8.1]
  def up
    add_column :milestone_rules, :slug, :string

    rule_klass = Class.new(ActiveRecord::Base) { self.table_name = "milestone_rules" }
    rule_klass.reset_column_information
    rule_klass.find_each do |row|
      candidate = Pito::SlugBuilder.build(row.name.presence || "milestone-rule-#{row.id}", limit: 80)
      candidate = "milestone-rule-#{row.id}" if candidate.blank?
      slug = unique_slug(candidate, rule_klass, row.id)
      row.update_columns(slug: slug)
    end

    change_column_null :milestone_rules, :slug, false
    add_index :milestone_rules, :slug, unique: true
  end

  def down
    remove_index :milestone_rules, :slug
    remove_column :milestone_rules, :slug
  end

  private

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
