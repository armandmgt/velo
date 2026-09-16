package fr.armandmgt.velo.features.record.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

/** Room store for in-progress recordings. Single process-wide instance. */
@Database(
    entities = [RecordingSessionEntity::class, RecordingPointEntity::class, RecordingLapEntity::class],
    version = 2,
    exportSchema = false,
)
abstract class RecordingDatabase : RoomDatabase() {
    abstract fun recordingDao(): RecordingDao

    companion object {
        @Volatile
        private var instance: RecordingDatabase? = null

        /**
         * Lap boundaries (#115). A real migration rather than a destructive
         * fallback: an upgrade must not throw away a ride the rider has recorded
         * but not yet uploaded. The statements are Room's own generated DDL, which
         * is what it validates the opened database against.
         */
        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `recording_laps` (" +
                        "`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                        "`sessionId` TEXT NOT NULL, " +
                        "`ordinal` INTEGER NOT NULL, " +
                        "`endedAt` INTEGER NOT NULL, " +
                        "`cumulativeDistance` REAL NOT NULL, " +
                        "`cumulativeElapsed` REAL NOT NULL, " +
                        "FOREIGN KEY(`sessionId`) REFERENCES `recording_sessions`(`id`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_recording_laps_sessionId_ordinal` " +
                        "ON `recording_laps` (`sessionId`, `ordinal`)",
                )
            }
        }

        fun get(context: Context): RecordingDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    RecordingDatabase::class.java,
                    "recording.db",
                ).addMigrations(MIGRATION_1_2).build().also { instance = it }
            }
    }
}
