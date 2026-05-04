# Phase 4 §3.1, §4 — workspace shell. References zero-or-more Games and
# Collections via the polymorphic `project_references` join.
class Project < ApplicationRecord
  belongs_to :tenant

  has_many :project_references, dependent: :destroy
  has_many :games,
           through: :project_references,
           source: :referenceable,
           source_type: "Game"
  has_many :collections,
           through: :project_references,
           source: :referenceable,
           source_type: "Collection"

  has_many :footages, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_many :timelines, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }

  # Phase 4 §2 "Default-create everywhere" — DB default is "Untitled project";
  # this keeps Project.new (no name) rendering the same default in spec
  # introspection without going through the DB.
  attribute :name, :string, default: "Untitled project"
end
