# Phase 25 — 01a (LD-3). Pure-function IP → prefix CIDR string.
#
# Mask widths are fixed: `/24` for IPv4, `/64` for IPv6. Residential
# IPs rotate within their carrier's allocation; matching on a stable
# prefix keeps "same household / same ISP region" recognizable across
# DHCP cycles without binding to the exact public IP.
#
# IPv4-mapped IPv6 (`::ffff:1.2.3.4`) is unwrapped to its IPv4 form so
# clients that present an IPv6-mapped address don't get a separate
# trusted-location row from their IPv4 one. `IPAddr#ipv4_mapped?` is
# the canonical detector.
#
# Loopback addresses are not special-cased — `127.0.0.1` → `127.0.0.0/24`,
# `::1` → `::/64`. The downstream geo enricher reports "location unknown"
# for these; the IP prefix is still computed deterministically.
require "ipaddr"

module Pito
  module Auth
    module IpPrefix
      IPV4_BITS = 24
      IPV6_BITS = 64

      module_function

      # `ip` may be an `IPAddr`, a plain string, or anything responding
      # to `to_s`. Returns the CIDR notation string.
      #
      # Raises `ArgumentError` on parse failure so the caller can decide
      # whether to swallow (logger path) or propagate (validator path).
      def call(ip)
        raise ArgumentError, "ip is required" if ip.nil?

        addr = ip.is_a?(IPAddr) ? ip : IPAddr.new(ip.to_s)

        # IPv6-mapped IPv4 → walk back to the IPv4 family so the prefix
        # comes out as a normal /24 rather than `::ffff:1.2.3.0/120`.
        if addr.ipv6? && addr.ipv4_mapped?
          addr = addr.native
        end

        if addr.ipv4?
          masked = addr.mask(IPV4_BITS)
          "#{masked}/#{IPV4_BITS}"
        else
          masked = addr.mask(IPV6_BITS)
          "#{masked}/#{IPV6_BITS}"
        end
      rescue IPAddr::Error => e
        raise ArgumentError, "invalid ip: #{ip.inspect} (#{e.message})"
      end
    end
  end
end
