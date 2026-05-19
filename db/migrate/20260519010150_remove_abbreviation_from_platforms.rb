class RemoveAbbreviationFromPlatforms < ActiveRecord::Migration[8.1]
  def change
    remove_column :platforms, :abbreviation, :string
  end
end
