# frozen_string_literal: true

# Footage now stores only what we use: filename (unique per game) + duration.
# Drop the metadata columns that are no longer read anywhere (resolution, fps,
# aspect_ratio, orientation, needs_grading, audio_track_names). Reversible:
# `down` re-adds each with its original type/options.
class DropUnusedFootageColumns < ActiveRecord::Migration[8.1]
  def change
    remove_column :footages, :resolution, :string
    remove_column :footages, :fps, :decimal, precision: 6, scale: 3
    remove_column :footages, :aspect_ratio, :string
    remove_column :footages, :orientation, :string
    remove_column :footages, :needs_grading, :boolean, default: false, null: false
    remove_column :footages, :audio_track_names, :text, array: true, default: [], null: false
  end
end
