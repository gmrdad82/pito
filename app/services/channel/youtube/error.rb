# Abstract base
# class for the YouTube client error hierarchy. Callers rescue the
# leaf classes; this base lets observers catch "any YouTube failure".
class Channel
  module Youtube
    class Error < StandardError; end
  end
end
