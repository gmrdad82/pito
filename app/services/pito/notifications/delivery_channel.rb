# Phase 16 §1 — Notifications data model + delivery channels.
#
# Namespace for PORO delivery channel dispatchers. Each subclass of
# `Pito::Notifications::DeliveryChannel::Base` handles per-provider
# HTTP dispatch.
#
# NOTE: The Active Record model `NotificationDeliveryChannel`
# (app/models/notification_delivery_channel.rb) is a SEPARATE class
# that persists per-provider webhook configuration. The model delegates
# its `.for(kind)` factory to `Pito::Notifications::DeliveryChannel::Base`.
module Pito
  module Notifications
    module DeliveryChannel
    end
  end
end
