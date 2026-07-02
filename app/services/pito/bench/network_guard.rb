# frozen_string_literal: true

require "socket"
require "net/http"

module Pito
  module Bench
    # In-process outbound-network kill switch for the READONLY bench run.
    #
    # `while_blocked { … }` makes ANY attempt to open a TCP socket raise
    # BlockedError for the duration of the block. Coverage:
    #
    #   * `TCPSocket.new` — the primitive every Ruby HTTP client builds on
    #     (Net::HTTP via TCPSocket.open→new; httpclient — the google-apis
    #     transport — calls TCPSocket.new directly).
    #   * `Net::HTTP#request` / `#start` — redundant with the socket guard but
    #     raises a clearer message naming the attempted host.
    #
    # Postgres is NOT affected: the pg gem connects through libpq (C), never
    # through Ruby's TCPSocket — so SolidCache/SolidQueue reads keep working.
    #
    # The core-class patches are prepended ONCE (idempotent) and stay inert
    # unless `active?` — requiring this file changes nothing outside a bench
    # run, and specs can wrap `while_blocked` freely (WebMock unaffected).
    module NetworkGuard
      class BlockedError < StandardError
        def initialize(target)
          super("pito:bench is READONLY — outbound network is blocked (attempted: #{target})")
        end
      end

      module TcpSocketGuard
        def new(*args, **kwargs, &block)
          raise BlockedError, args.first.to_s if Pito::Bench::NetworkGuard.active?

          super
        end
        # TCPSocket.open is dispatched through .new (IO.open calls self.new),
        # so guarding .new covers both entry points.
      end

      module NetHttpGuard
        def start(*args, &block)
          raise BlockedError, address if Pito::Bench::NetworkGuard.active?

          super
        end

        def request(req, *args, &block)
          raise BlockedError, "#{address}#{req&.path}" if Pito::Bench::NetworkGuard.active?

          super
        end
      end

      @active    = false
      @installed = false

      module_function

      def active?
        @active
      end

      # Runs the block with outbound network blocked; always re-opens on exit.
      def while_blocked
        install!
        @active = true
        yield
      ensure
        @active = false
      end

      # Prepends the guards once. Inert until `while_blocked` flips the flag.
      def install!
        return if @installed

        TCPSocket.singleton_class.prepend(TcpSocketGuard)
        Net::HTTP.prepend(NetHttpGuard)
        @installed = true
      end
    end
  end
end
