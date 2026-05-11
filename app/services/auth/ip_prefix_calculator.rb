# Phase 25 — 01a. Service-layer facade over `Pito::Auth::IpPrefix`.
#
# Two reasons the spec lists this in `app/services/auth/` even though
# the lib already exposes the pure function:
#
# 1. The auth services compose into `Auth::AttemptLogger` in one place;
#    keeping the IP-prefix call alongside `FingerprintComposer` and
#    `GeoEnricher` makes the logger's dependency graph readable in one
#    namespace.
# 2. Spec discipline: service-level specs assert the contract the
#    caller relies on (one method, one return shape), while the lib
#    spec proves the algorithm. Two specs document two concerns.
module Auth
  class IpPrefixCalculator
    def self.call(ip)
      Pito::Auth::IpPrefix.call(ip)
    end
  end
end
