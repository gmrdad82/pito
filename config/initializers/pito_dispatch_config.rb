# frozen_string_literal: true

Rails.application.config.to_prepare do
  Pito::Dispatch::Config.reload!
  Pito::Dispatch::Matrix.reload!
end
