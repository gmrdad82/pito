# frozen_string_literal: true

# Forward application logs to AppSignal, without losing the docker STDOUT
# stream. Production logging (config/environments/production.rb) sets
# `Rails.logger = ActiveSupport::TaggedLogging.logger(STDOUT)`, and that
# STDOUT stream is load-bearing — it's what `docker logs` / the json-file
# driver captures — so it must keep flowing exactly as before.
#
# When AppSignal is genuinely active (config/appsignal.rb: production +
# APPSIGNAL_PUSH_API_KEY present), we additionally send logs to AppSignal's
# log tailing feature by swapping in an `Appsignal::Logger` and broadcasting
# FROM it TO the STDOUT logger Rails already configured. Per AppSignal's own
# Ruby logging docs, this must use `Appsignal::Logger#broadcast_to` — NOT
# `ActiveSupport::BroadcastLogger` — because the latter re-runs `tagged`
# blocks once per broadcasted logger, which both duplicates every tagged log
# line and (worse) can re-run request middleware.
#
# `Appsignal.started?` is true only once `Appsignal.start` has actually
# activated (valid config + active for this env), so dev/test/keyless boots
# never touch `Rails.logger` here and this file is a hard no-op for every
# self-hoster who hasn't set APPSIGNAL_PUSH_API_KEY.
if Appsignal.started?
  stdout_logger = Rails.logger

  appsignal_logger = Appsignal::Logger.new("rails")
  appsignal_logger.broadcast_to(stdout_logger)

  Rails.logger = ActiveSupport::TaggedLogging.new(appsignal_logger)
end
