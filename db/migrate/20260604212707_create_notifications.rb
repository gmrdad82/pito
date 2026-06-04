# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.text :message, null: false
      t.datetime :read_at

      t.timestamps
    end
  end
end
