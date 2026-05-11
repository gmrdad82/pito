# Phase 26 — 01b. Slack webhook pane + validation (and parallel 01c —
# Discord). Persists per-provider webhook configuration in a single
# install-level table. ADR-0003: install-level, no `user_id`.
#
# Phase 16 shipped `NotificationDeliveryChannel::Slack` etc. as POROs
# that pulled the webhook URL out of `Rails.application.credentials`.
# This phase introduces an AR-backed `NotificationDeliveryChannel`
# table so operators can manage the webhook from the Settings UI
# without a `rails credentials:edit` round-trip. The PORO classes are
# refactored to read from this table; the credentials fallback stays
# untouched as a backstop (so an existing install with a credentials-
# only configuration continues to deliver).
#
# `kind` carries the provider name (currently `slack` and `discord`).
# The unique index on `kind` enforces the install-level singleton-per-
# provider invariant.
#
# `webhook_url` is encrypted at the model layer with Active Record
# Encryption (probabilistic — never compared, never queried). Column
# type is `text` to fit ARE's JSON-encoded ciphertext blob.
#
# `everything` and `daily_digest` are independent Boolean flags
# capturing the per-provider notification routing state. The
# `last_validated_at` timestamp records when the most recent test
# ping succeeded — the Settings pane refuses to persist the row
# until a 2xx ping has landed for the URL.
class CreateNotificationDeliveryChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_delivery_channels do |t|
      t.string :kind, null: false
      t.text :webhook_url, null: false
      t.boolean :everything, null: false, default: false
      t.boolean :daily_digest, null: false, default: false
      t.datetime :last_validated_at

      t.timestamps
    end

    add_index :notification_delivery_channels, :kind, unique: true
  end
end
