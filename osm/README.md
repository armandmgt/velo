# OSM Docker Compose Setup

This directory contains a `docker-compose.yml` file to run a PostGIS database, a Nominatim API, and a Martin Tile Server. 

## Components

1.  **PostGIS (db)**: A PostgreSQL 16 database with PostGIS extensions. Both services use the same PostgreSQL instance but have separate databases (`nominatim`).
2.  **Nominatim API**: Uses the official `mediagis/nominatim` image. It automatically imports OSM data on first run and persists its state using a dedicated volume (`nominatim-db-data`).
3.  **Martin Tile Server**: Uses the official `maplibre/martin` image. It serves vector tiles in the Shortbread schema.
4.  **Planetiler (importer)**: A helper service to generate `shortbread.pmtiles` from OSM data. It's much faster than `osm2pgsql` and reduces server load by serving pre-generated tiles.

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
The tile server uses a `shortbread.pmtiles` file. Run the following command to start the generation:
```bash
docker compose --profile import run --rm planetiler
```
*Note: This command will download the PBF file and generate the `shortbread.pmtiles` file in the current directory. It may take some time depending on the size of the region.*

## Ports

- **Nominatim API**: [http://localhost:8080](http://localhost:8080)
- **Martin Tile Server**: [http://localhost:8081](http://localhost:8081)
- **PostGIS**: `localhost:5432`

## Notes on Martin

Once `planetiler` has finished generating the PMTiles file, Martin will serve the tiles at [http://localhost:8081/shortbread](http://localhost:8081/shortbread).

To use the tiles, point your map client (e.g., MapLibre GL JS) to the Martin server. Since we've switched to the Shortbread schema, you'll need a style compatible with Shortbread. You can generate one using the `bin/update_map_style` script, which configures the `/shortbread` source with all necessary layers.
