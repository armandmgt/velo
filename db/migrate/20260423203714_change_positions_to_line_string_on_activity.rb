class ChangePositionsToLineStringOnActivity < ActiveRecord::Migration[8.1]
  def change
    change_table :activities, bulk: true do |t|
      t.remove :positions, type: :string
      t.column :path, :line_string
    end
  end
end
