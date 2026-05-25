require "sidekiq/api"
require Rails.root.join("app/services/pito/cable_broadcaster")

module Pito
  class StatusBarBroadcastMiddleware
    def call(worker, job, queue)
      yield
    ensure
      payload = SidekiqStatusPayload.call
      Rails.logger.info "[StatusBarMiddleware] broadcasting: #{payload.inspect}" rescue nil
      Pito::CableBroadcaster.broadcast_status_bar(payload)
    end

    module SidekiqStatusPayload
      module_function

      def call
        stats = Sidekiq::Stats.new
        {
          kind: "status_bar",
          payload: {
            connected: true,
            sidekiq: {
              busy: stats.workers_size,
              enqueued: stats.enqueued,
              retry: stats.retry_size,
              dead: stats.dead_size,
              scheduled: stats.scheduled_size
            }
          },
          ts: Time.current.iso8601
        }
      rescue => e
        {
          kind: "status_bar",
          payload: { connected: false, error: e.message }
        }
      end
    end
  end
end
