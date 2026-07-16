# frozen_string_literal: true

module Pito
  # PB-1: bot probes send malformed requests (bogus multipart boundaries,
  # unparseable query/param structures) that Rack::MethodOverride blows up
  # on while reading params. Unrescued, that raises deep in the middleware
  # stack and surfaces as an HTTP 500 + an AppSignal incident for input
  # that is simply invalid, not a server fault. This middleware sits ABOVE
  # Rack::MethodOverride (config/application.rb inserts it immediately
  # before) so it wraps the call where the parse raises, converting the
  # known malformed-request error classes into a plain 400 instead of a
  # 500 — de-noising AppSignal for traffic that was never going to succeed.
  class BadRequestGuard
    MALFORMED_REQUEST_ERRORS = [
      Rack::Multipart::BoundaryTooLongError,
      Rack::Utils::ParameterTypeError,
      Rack::Utils::InvalidParameterError,
      Rack::QueryParser::ParameterTypeError,
      Rack::QueryParser::InvalidParameterError
    ].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue *MALFORMED_REQUEST_ERRORS
      [ 400, { "content-type" => "text/plain; charset=utf-8" }, [ "Bad Request\n" ] ]
    end
  end
end
