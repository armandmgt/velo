class AddVisibilityToPlannedRoutes < ActiveRecord::Migration[8.1]
  def change
    add_column :planned_routes, :visibility, :string, null: false, default: "private"
  end
end
