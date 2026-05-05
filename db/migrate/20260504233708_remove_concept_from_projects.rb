class RemoveConceptFromProjects < ActiveRecord::Migration[8.1]
  def change
    remove_column :projects, :concept, :text
  end
end
