# Phase 15 §1 — Calendar Data Model.
#
# Sidekiq wrapper around `Calendar::Derivation#sync!` for the cases
# where the callback flow needs to be deferred (e.g., bulk Video
# reseed). The host class is a string for ActiveJob serialization.
class CalendarDerivationJob < ApplicationJob
  queue_as :default

  def perform(host_class, host_id)
    klass = host_class.constantize
    host = klass.find_by(id: host_id)
    return unless host
    Calendar::Derivation.sync!(host)
  end
end
