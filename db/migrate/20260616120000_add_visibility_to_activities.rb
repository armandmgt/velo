class AddVisibilityToActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :activities, :visibility, :string, null: false, default: "private"
  end
end
