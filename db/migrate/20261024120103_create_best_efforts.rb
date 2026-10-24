class CreateBestEfforts < ActiveRecord::Migration[8.1]
  def change
    create_table :best_efforts do |t|
      t.references :activity, null: false, foreign_key: { on_delete: :cascade }
      t.string :distance, null: false
      t.float :elapsed_seconds, null: false
      t.integer :start_index, null: false
      t.integer :end_index, null: false
      t.integer :rank
      t.datetime :removed_at
      t.timestamps
    end

    add_index :best_efforts, %i[activity_id distance], unique: true
    add_index :best_efforts, %i[distance elapsed_seconds], where: "removed_at IS NULL"
  end
end
