class ChangePositionsToLineStringOnActivity < ActiveRecord::Migration[8.1]
  def change
    change_table :activities, bulk: true do |t|
      t.remove :positions, type: :string
      t.string :path
    end
  end
end