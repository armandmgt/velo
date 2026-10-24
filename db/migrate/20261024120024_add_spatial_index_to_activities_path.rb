class AddSpatialIndexToActivitiesPath < ActiveRecord::Migration[8.1]
  def change
    add_index :activities, :path, using: :gist
  end
end
