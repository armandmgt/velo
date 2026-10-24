package fr.armandmgt.velo.features.record.data

import android.content.Context
import androidx.annotation.VisibleForTesting
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

/** Room store for in-progress recordings. Single process-wide instance. */
@Database(
    entities = [RecordingSessionEntity::class, RecordingPointEntity::class, RecordingLapEntity::class],
    version = 3,
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

        /**
         * What an unsent recording needs to rebuild its handoff (#117). Explicit for
         * the same reason as [MIGRATION_1_2]: a phone may be holding exactly the
         * recording this exists to rescue.
         */
        private val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `recording_sessions` ADD COLUMN `sport` TEXT")
                for (column in listOf("elapsed", "distance", "movingTime", "averageSpeed")) {
                    db.execSQL("ALTER TABLE `recording_sessions` ADD COLUMN `$column` REAL NOT NULL DEFAULT 0")
                }
                db.execSQL("ALTER TABLE `recording_sessions` ADD COLUMN `stoppedAt` INTEGER")
            }
        }

        /** Every upgrade path, oldest first — what [get] opens the store with. */
        internal val MIGRATIONS = arrayOf(MIGRATION_1_2, MIGRATION_2_3)

        /** Lets a test hand the service an in-memory store before it opens the real one. */
        @VisibleForTesting
        internal fun replaceForTesting(database: RecordingDatabase?) {
            instance = database
        }

        fun get(context: Context): RecordingDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    RecordingDatabase::class.java,
                    "recording.db",
                ).addMigrations(*MIGRATIONS).build().also { instance = it }
            }
    }
}
