module Pito
  module Search
    def self.engine
      @engine ||= build_engine
    end

    def self.reset_engine!
      @engine = nil
    end

    def self.build_engine
      Engine.new
    end
    private_class_method :build_engine
  end
end
