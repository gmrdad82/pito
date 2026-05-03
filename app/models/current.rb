class Current < ActiveSupport::CurrentAttributes
  attribute :tenant, :user, :token
end
