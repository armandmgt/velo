class AddRecordingUuidToActivities < ActiveRecord::Migration[8.1]
  # Idempotency key for native recordings (#116); null for every other source.
  # Scoped to the owner rather than globally unique: the value arrives in a
  # user-controlled field, and a global index would let one account's upload
  # collide with another's row.
  def change
    add_column :activities, :recording_uuid, :uuid
    add_index :activities, [ :user_id, :recording_uuid ], unique: true
  end
end
