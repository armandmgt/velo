# OSM Docker Compose Setup

This directory contains a `docker-compose.yml` file to run a PostGIS database, a Nominatim API, and a Martin Tile Server. 

## Components

1.  **PostGIS (db)**: A PostgreSQL 16 database with PostGIS extensions. Both services use the same PostgreSQL instance but have separate databases (`nominatim` and `tiles`).
2.  **Nominatim API**: Uses the official `mediagis/nominatim` image. It automatically imports OSM data on first run and persists its state using a dedicated volume (`nominatim-db-data`).
3.  **Martin Tile Server**: Uses the official `maplibre/martin` image. It serves vector tiles in the Shortbread schema, aggregated into a single `shortbread` tileset.
4.  **osm2pgsql (importer)**: A helper service to import OSM data into the `tiles` database using the `osm2pgsql-themepark` Shortbread theme.

## Getting Started

1.  Configure the `.env` file with your database credentials and the `OSM_PBF_URL` of the region you want to import.
2.  Start the services:
    ```bash
    docker compose up -d
    ```

## Data Import

### 1. Nominatim
Nominatim will automatically detect if its database is empty and start the import process using the `OSM_PBF_URL` provided in your `.env`. You can check the progress with:
```bash
docker compose logs -f nominatim
```

### 2. Martin (Tile Server)
The tile server database (`tiles`) needs to be populated using `osm2pgsql`. We've included a helper service for this. Run the following command to start the import:
```bash
docker compose --profile import run --rm osm2pgsql
```
*Note: This command will download the PBF file and import it into the `tiles` database. It may take some time depending on the size of the region.*

## Ports

- **Nominatim API**: [http://localhost:8080](http://localhost:8080)
- **Martin Tile Server**: [http://localhost:8081](http://localhost:8081)
- **PostGIS**: `localhost:5432`

## Notes on Martin

Martin is configured to serve an aggregated `shortbread` tileset. Once `osm2pgsql` has finished importing, you can see the available tilesets at [http://localhost:8081/index.json](http://localhost:8081/index.json). The `shortbread` endpoint will be available at `http://localhost:8081/shortbread`.

To use the tiles, point your map client (e.g., MapLibre GL JS) to the `http://localhost:8081/shortbread` source. Note that since we've switched to the Shortbread schema, you'll need a style compatible with Shortbread.
