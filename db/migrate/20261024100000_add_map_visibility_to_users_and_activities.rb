class AddMapVisibilityToUsersAndActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :map_hide_start_end_distance, :integer, null: false, default: 200
    add_column :activities, :map_hidden, :boolean, null: false, default: false
  end
end
