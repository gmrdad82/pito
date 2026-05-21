module Pito
  # `Pito::ExternalApiTracker` — unified quota-tracking namespace.
  #
  # Each external API client (YouTube, IGDB, Voyage) has its own tracker
  # sub-module that knows how to report current usage + quota cap.
  # Home's API quota panel + Settings' stack stats panel both read here.
  #
  # ## Contract per tracker
  #
  # Each `Pito::ExternalApiTracker::<Client>` exposes:
  #
  # - `.usage` → integer (calls or units consumed in the current window)
  # - `.quota` → integer or nil (cap for the window; nil = no documented cap)
  # - `.window` → Symbol (`:daily` / `:monthly` / `:rolling_24h` etc.)
  # - `.percent` → Float 0.0..1.0 (usage / quota; 0.0 if quota nil)
  # - `.status` → Symbol (`:ok` / `:warn` / `:critical`) based on percent
  module ExternalApiTracker
  end
end
