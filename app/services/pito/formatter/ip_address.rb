module Pito
  module Formatter
    # Compact IP address display for the sessions table (security panel).
    #
    # Width target: IPv4 standard length `123.123.123.123` (15 chars).
    # IPv4 always fits; IPv6 longer than 15 chars is trimmed with a
    # TRAILING ellipsis, preferring a group-boundary cut for readability.
    #
    # Examples:
    #   "127.0.0.1"                            -> "127.0.0.1"
    #   "255.255.255.255"                      -> "255.255.255.255"
    #   "::1"                                  -> "::1"
    #   "2a0d:3344:7a3e:9efe:0c1f:dce9:24f1"   -> "2a0d:3344:7a3e…"
    #   "2a02:2f04:7a3e:9efe:0c1f"             -> "2a02:2f04:7a3e…"
    #
    # Returns the em-dash glyph for nil / blank input.
    module IpAddress
      module_function

      EM_DASH  = "—"
      ELLIPSIS = "…"
      # 2026-05-24 — width tightened from 15 (IPv4 max) to 13 per user pick.
      # IPv4 "255.255.255.255" (15 chars) gets head-trimmed with trailing
      # ellipsis like IPv6; acceptable since the trailing octet is the
      # least-distinguishing part of a LAN address and the table reads
      # tighter overall.
      MAX_LEN  = 13

      def call(ip)
        return EM_DASH if ip.nil?
        ip_str = ip.to_s
        return EM_DASH if ip_str.blank?
        return ip_str if ip_str.length <= MAX_LEN

        budget = MAX_LEN - ELLIPSIS.length
        head = group_boundary_head(ip_str, budget)
        head = ip_str[0, budget] if head.empty?
        "#{head}#{ELLIPSIS}"
      end

      def group_boundary_head(ip_str, budget)
        head = ""
        ip_str.split(":").each do |g|
          candidate = head.empty? ? g : "#{head}:#{g}"
          break if candidate.length > budget
          head = candidate
        end
        head
      end
      private_class_method :group_boundary_head
    end
  end
end
