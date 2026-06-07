# frozen_string_literal: true

class DropChannelBannerUrl < ActiveRecord::Migration[8.0]
  def change
    remove_column :channels, :banner_url, :string
  end
end
