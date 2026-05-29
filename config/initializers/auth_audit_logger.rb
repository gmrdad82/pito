# Auth audit logger. Writes structured auth events (e.g.
# session.cookie.invalid from Sessions::AuthConcern) as one JSON line per
# event to log/auth_audit.log. The call site already JSON-encodes the
# payload, so the formatter just appends a newline. Logrotate is a
# host-side concern (not configured here).
require "logger"

audit_path = Rails.root.join("log/auth_audit.log")
FileUtils.mkdir_p(File.dirname(audit_path))

AUTH_AUDIT_LOGGER = Logger.new(audit_path)
AUTH_AUDIT_LOGGER.formatter = ->(_severity, _time, _progname, msg) { "#{msg}\n" }
