# frozen_string_literal: true

# A manually-entered euro price for a game (e.g. its store/retail price).
# Nullable — most games carry no price until the owner sets one; when present
# it is always > 0 (enforced by a model validation, since "free/0" is expressed
# as "unset"). decimal(8,2) covers up to 999_999.99.
class AddPriceToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :price, :decimal, precision: 8, scale: 2, null: true
  end
end
