#!/bin/bash
set -e

# Function to create a database if it doesn't exist and enable extensions
create_db_and_extensions() {
    local db_name=$1
    echo "Checking database $db_name..."
    
    # Check if database exists
    DB_EXISTS=$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -tAc "SELECT 1 FROM pg_database WHERE datname = '$db_name'")
    
    if [ "$DB_EXISTS" != "1" ]; then
        echo "Creating database $db_name..."
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "CREATE DATABASE \"$db_name\""
    fi

    echo "Enabling extensions on $db_name..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db_name" <<-EOSQL
        CREATE EXTENSION IF NOT EXISTS postgis;
        CREATE EXTENSION IF NOT EXISTS hstore;
EOSQL
}

# Create Nominatim database
create_db_and_extensions "$NOMINATIM_DB"

# Create Tiles database
create_db_and_extensions "$TILES_DB"
