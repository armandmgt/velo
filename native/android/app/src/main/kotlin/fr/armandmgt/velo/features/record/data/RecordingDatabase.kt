package fr.armandmgt.velo.features.record.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

/** Room store for in-progress recordings (#56). Single process-wide instance. */
@Database(
    entities = [RecordingSessionEntity::class, RecordingPointEntity::class],
    version = 1,
    exportSchema = false,
)
abstract class RecordingDatabase : RoomDatabase() {
    abstract fun recordingDao(): RecordingDao

    companion object {
        @Volatile
        private var instance: RecordingDatabase? = null

        fun get(context: Context): RecordingDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    RecordingDatabase::class.java,
                    "recording.db",
                ).build().also { instance = it }
            }
    }
}
