# frozen_string_literal: true

class AddDraftToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :draft, :text
  end
end
