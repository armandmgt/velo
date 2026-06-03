class AddNamePendingToActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :activities, :name_pending, :boolean, null: false, default: false
  end
end
