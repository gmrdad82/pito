module Formatting
  module IpAddress
    module_function

    EM_DASH = "—"

    def call(ip)
      return EM_DASH if ip.nil?
      ip_str = ip.to_s
      return EM_DASH if ip_str.blank?
      return ip_str unless ip_str.include?(":") # IPv4 — keep as-is

      groups = ip_str.split(":")
      return ip_str if groups.length <= 4

      # IPv6 with > 4 groups — truncate
      first_two = groups.first(2).join(":")
      last_two = groups.last(2).join(":")
      "#{first_two}:…:#{last_two}"
    end
  end
end
