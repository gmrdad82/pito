module Tui
  class SubPanelComponent < ViewComponent::Base
    renders_one :actions

    def initialize(title:, class_name: nil)
      @title = title
      @class_name = class_name
    end

    attr_reader :title

    def sub_panel_class
      [ "pito-sub-panel", @class_name ].compact.join(" ")
    end
  end
end
