class DropBitDepthFromFootages < ActiveRecord::Migration[8.1]
  def change
    remove_column :footages, :bit_depth, :integer
  end
end
