# Abstract base for all pito ActiveRecord models. All application tables
# inherit from here; never instantiated directly (`primary_abstract_class`).
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
