class EnablePostgresExtensions < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto"
    enable_extension "citext"
    enable_extension "vector"
  end
end
