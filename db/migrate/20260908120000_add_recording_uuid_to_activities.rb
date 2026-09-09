class AddRecordingUuidToActivities < ActiveRecord::Migration[8.1]
  # Idempotency key for native recordings; null for every other source. Scoped
  # to the owner because the value arrives in a user-controlled field.
  def change
    add_column :activities, :recording_uuid, :uuid
    add_index :activities, [ :user_id, :recording_uuid ], unique: true
  end
end
