# frozen_string_literal: true

# First slice of FCM push support: persists the tokens the Android shell
# registers so a later sender phase has somewhere to deliver to. No FCM/HTTP
# code lands here — plumbing only (see DeviceTokensController).
class CreateDeviceTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :device_tokens do |t|
      t.string   :token,        null: false
      t.string   :platform,     null: false, default: "android"
      t.datetime :last_seen_at, null: false
      t.timestamps
    end

    add_index :device_tokens, :token, unique: true
  end
end
