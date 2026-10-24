SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activities (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    name character varying NOT NULL,
    description character varying,
    sport character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    start_time timestamp(6) without time zone NOT NULL,
    end_time timestamp(6) without time zone NOT NULL,
    location character varying NOT NULL,
    distance numeric,
    active_time character varying NOT NULL,
    total_elevation_gain numeric,
    max_speed numeric,
    path public.geometry(LineString),
    name_pending boolean DEFAULT false NOT NULL,
    visibility character varying DEFAULT 'private'::character varying NOT NULL,
    recording_uuid uuid,
    gear_id bigint,
    map_hidden boolean DEFAULT false NOT NULL,
    effort_score numeric(7,1),
    effort_score_source character varying,
    tile_path_z7 public.geometry(LineString,3857) GENERATED ALWAYS AS (public.st_simplify(public.st_transform(public.st_setsrid(path, 4326), 3857), (611.5)::double precision)) STORED,
    tile_path_z9 public.geometry(LineString,3857) GENERATED ALWAYS AS (public.st_simplify(public.st_transform(public.st_setsrid(path, 4326), 3857), (152.9)::double precision)) STORED,
    tile_path_z11 public.geometry(LineString,3857) GENERATED ALWAYS AS (public.st_simplify(public.st_transform(public.st_setsrid(path, 4326), 3857), (38.2)::double precision)) STORED,
    tile_path_z13 public.geometry(LineString,3857) GENERATED ALWAYS AS (public.st_simplify(public.st_transform(public.st_setsrid(path, 4326), 3857), (9.6)::double precision)) STORED,
    tile_path_z14 public.geometry(LineString,3857) GENERATED ALWAYS AS (public.st_simplify(public.st_transform(public.st_setsrid(path, 4326), 3857), (0.6)::double precision)) STORED,
    normalized_power double precision,
    power_curve jsonb
);


--
-- Name: activities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.activities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: activities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.activities_id_seq OWNED BY public.activities.id;


--
-- Name: activity_data_points; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity_data_points (
    id bigint NOT NULL,
    activity_id bigint NOT NULL,
    recorded_at timestamp(6) without time zone NOT NULL,
    location public.geography(Point,4326),
    speed numeric,
    heart_rate integer,
    cadence numeric,
    power numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    altitude numeric
);


--
-- Name: activity_data_points_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.activity_data_points_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: activity_data_points_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.activity_data_points_id_seq OWNED BY public.activity_data_points.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: best_efforts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.best_efforts (
    id bigint NOT NULL,
    activity_id bigint NOT NULL,
    distance character varying NOT NULL,
    elapsed_seconds double precision NOT NULL,
    start_index integer,
    end_index integer,
    rank integer,
    removed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    average_power double precision
);


--
-- Name: best_efforts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.best_efforts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: best_efforts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.best_efforts_id_seq OWNED BY public.best_efforts.id;


--
-- Name: data_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_migrations (
    version character varying NOT NULL
);


--
-- Name: gear_components; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gear_components (
    id bigint NOT NULL,
    gear_id bigint NOT NULL,
    kind character varying NOT NULL,
    nickname character varying,
    installed_on date NOT NULL,
    service_interval_km integer NOT NULL,
    retired_at timestamp(6) without time zone,
    final_distance numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: gear_components_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gear_components_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gear_components_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gear_components_id_seq OWNED BY public.gear_components.id;


--
-- Name: gear_defaults; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gear_defaults (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    gear_id bigint NOT NULL,
    sport character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: gear_defaults_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gear_defaults_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gear_defaults_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gear_defaults_id_seq OWNED BY public.gear_defaults.id;


--
-- Name: gears; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gears (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    kind character varying NOT NULL,
    name character varying NOT NULL,
    brand character varying,
    model character varying,
    retired_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: gears_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gears_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gears_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gears_id_seq OWNED BY public.gears.id;


--
-- Name: igpsport_connections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.igpsport_connections (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    email text NOT NULL,
    password text NOT NULL,
    access_token text,
    token_expires_at timestamp(6) without time zone,
    enabled boolean DEFAULT true NOT NULL,
    last_synced_at timestamp(6) without time zone,
    last_sync_status character varying,
    last_sync_error text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: igpsport_connections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.igpsport_connections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: igpsport_connections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.igpsport_connections_id_seq OWNED BY public.igpsport_connections.id;


--
-- Name: map_privacy_zones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.map_privacy_zones (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    name character varying,
    center public.geography(Point,4326) NOT NULL,
    radius integer DEFAULT 200 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: map_privacy_zones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.map_privacy_zones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: map_privacy_zones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.map_privacy_zones_id_seq OWNED BY public.map_privacy_zones.id;


--
-- Name: planned_routes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planned_routes (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    name character varying NOT NULL,
    sport character varying NOT NULL,
    waypoints jsonb DEFAULT '[]'::jsonb NOT NULL,
    path public.geography(LineString,4326),
    distance_meters integer,
    elevation_gain_meters integer,
    routing_profile character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    elevation_samples jsonb,
    visibility character varying DEFAULT 'private'::character varying NOT NULL
);


--
-- Name: planned_routes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.planned_routes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: planned_routes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.planned_routes_id_seq OWNED BY public.planned_routes.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: segment_efforts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.segment_efforts (
    id bigint NOT NULL,
    segment_id bigint NOT NULL,
    activity_id bigint NOT NULL,
    start_index integer NOT NULL,
    end_index integer NOT NULL,
    elapsed_seconds double precision NOT NULL,
    private boolean DEFAULT false NOT NULL,
    rank integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: segment_efforts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.segment_efforts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: segment_efforts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.segment_efforts_id_seq OWNED BY public.segment_efforts.id;


--
-- Name: segments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.segments (
    id bigint NOT NULL,
    user_id bigint,
    name character varying NOT NULL,
    sport_category character varying NOT NULL,
    path public.geography(LineString,4326) NOT NULL,
    start_point public.geography(Point,4326) NOT NULL,
    end_point public.geography(Point,4326) NOT NULL,
    altitudes double precision[] DEFAULT '{}'::double precision[] NOT NULL,
    distance double precision NOT NULL,
    elevation_gain double precision DEFAULT 0.0 NOT NULL,
    average_grade double precision DEFAULT 0.0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: segments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.segments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: segments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.segments_id_seq OWNED BY public.segments.id;


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    user_id bigint,
    ip_address character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    service_account boolean DEFAULT false NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email_address character varying NOT NULL,
    password_digest character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    admin boolean DEFAULT false NOT NULL,
    max_heart_rate integer,
    email_verified_at timestamp(6) without time zone,
    name character varying,
    map_hide_start_end_distance integer DEFAULT 200 NOT NULL,
    ftp integer
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: activities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities ALTER COLUMN id SET DEFAULT nextval('public.activities_id_seq'::regclass);


--
-- Name: activity_data_points id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_data_points ALTER COLUMN id SET DEFAULT nextval('public.activity_data_points_id_seq'::regclass);


--
-- Name: best_efforts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.best_efforts ALTER COLUMN id SET DEFAULT nextval('public.best_efforts_id_seq'::regclass);


--
-- Name: gear_components id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gear_components ALTER COLUMN id SET DEFAULT nextval('public.gear_components_id_seq'::regclass);


--
-- Name: gear_defaults id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gear_defaults ALTER COLUMN id SET DEFAULT nextval('public.gear_defaults_id_seq'::regclass);


--
-- Name: gears id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gears ALTER COLUMN id SET DEFAULT nextval('public.gears_id_seq'::regclass);


--
-- Name: igpsport_connections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.igpsport_connections ALTER COLUMN id SET DEFAULT nextval('public.igpsport_connections_id_seq'::regclass);


--
-- Name: map_privacy_zones id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_privacy_zones ALTER COLUMN id SET DEFAULT nextval('public.map_privacy_zones_id_seq'::regclass);


--
-- Name: planned_routes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planned_routes ALTER COLUMN id SET DEFAULT nextval('public.planned_routes_id_seq'::regclass);


--
-- Name: segment_efforts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segment_efforts ALTER COLUMN id SET DEFAULT nextval('public.segment_efforts_id_seq'::regclass);


--
-- Name: segments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segments ALTER COLUMN id SET DEFAULT nextval('public.segments_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: activities activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_pkey PRIMARY KEY (id);


--
-- Name: activity_data_points activity_data_points_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_data_points
    ADD CONSTRAINT activity_data_points_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: best_efforts best_efforts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.best_efforts
    ADD CONSTRAINT best_efforts_pkey PRIMARY KEY (id);


--
-- Name: data_migrations data_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_migrations
    ADD CONSTRAINT data_migrations_pkey PRIMARY KEY (version);


--
-- Name: gear_components gear_components_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gear_components
    ADD CONSTRAINT gear_components_pkey PRIMARY KEY (id);


--
-- Name: gear_defaults gear_defaults_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gear_defaults
    ADD CONSTRAINT gear_defaults_pkey PRIMARY KEY (id);


--
-- Name: gears gears_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gears
    ADD CONSTRAINT gears_pkey PRIMARY KEY (id);


--
-- Name: igpsport_connections igpsport_connections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.igpsport_connections
    ADD CONSTRAINT igpsport_connections_pkey PRIMARY KEY (id);


--
-- Name: map_privacy_zones map_privacy_zones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_privacy_zones
    ADD CONSTRAINT map_privacy_zones_pkey PRIMARY KEY (id);


--
-- Name: planned_routes planned_routes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planned_routes
    ADD CONSTRAINT planned_routes_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: segment_efforts segment_efforts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segment_efforts
    ADD CONSTRAINT segment_efforts_pkey PRIMARY KEY (id);


--
-- Name: segments segments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segments
    ADD CONSTRAINT segments_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_activities_on_gear_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_gear_id ON public.activities USING btree (gear_id);


--
-- Name: index_activities_on_path_geography; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_path_geography ON public.activities USING gist (((path)::public.geography));


--
-- Name: index_activities_on_tile_path_z11; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_tile_path_z11 ON public.activities USING gist (tile_path_z11);


--
-- Name: index_activities_on_tile_path_z13; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_tile_path_z13 ON public.activities USING gist (tile_path_z13);


--
-- Name: index_activities_on_tile_path_z14; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_tile_path_z14 ON public.activities USING gist (tile_path_z14);


--
-- Name: index_activities_on_tile_path_z7; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_tile_path_z7 ON public.activities USING gist (tile_path_z7);


--
-- Name: index_activities_on_tile_path_z9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_tile_path_z9 ON public.activities USING gist (tile_path_z9);


--
-- Name: index_activities_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_user_id ON public.activities USING btree (user_id);


--
-- Name: index_activities_on_user_id_and_recording_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_activities_on_user_id_and_recording_uuid ON public.activities USING btree (user_id, recording_uuid);


--
-- Name: index_activity_data_points_on_activity_id_and_recorded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_activity_data_points_on_activity_id_and_recorded_at ON public.activity_data_points USING btree (activity_id, recorded_at);


--
-- Name: index_best_efforts_on_activity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_best_efforts_on_activity_id ON public.best_efforts USING btree (activity_id);


--
-- Name: index_best_efforts_on_activity_id_and_distance; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_best_efforts_on_activity_id_and_distance ON public.best_efforts USING btree (activity_id, distance);


--
-- Name: index_best_efforts_on_distance_and_elapsed_seconds; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_best_efforts_on_distance_and_elapsed_seconds ON public.best_efforts USING btree (distance, elapsed_seconds) WHERE (removed_at IS NULL);


--
-- Name: index_gear_components_on_gear_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_gear_components_on_gear_id ON public.gear_components USING btree (gear_id);


--
-- Name: index_gear_defaults_on_gear_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_gear_defaults_on_gear_id ON public.gear_defaults USING btree (gear_id);


--
-- Name: index_gear_defaults_on_user_id_and_sport; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_gear_defaults_on_user_id_and_sport ON public.gear_defaults USING btree (user_id, sport);


--
-- Name: index_gears_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_gears_on_user_id ON public.gears USING btree (user_id);


--
-- Name: index_igpsport_connections_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_igpsport_connections_on_user_id ON public.igpsport_connections USING btree (user_id);


--
-- Name: index_map_privacy_zones_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_privacy_zones_on_user_id ON public.map_privacy_zones USING btree (user_id);


--
-- Name: index_planned_routes_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_planned_routes_on_user_id ON public.planned_routes USING btree (user_id);


--
-- Name: index_segment_efforts_on_activity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_segment_efforts_on_activity_id ON public.segment_efforts USING btree (activity_id);


--
-- Name: index_segment_efforts_on_leaderboard; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_segment_efforts_on_leaderboard ON public.segment_efforts USING btree (segment_id, elapsed_seconds) WHERE (NOT private);


--
-- Name: index_segment_efforts_on_segment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_segment_efforts_on_segment_id ON public.segment_efforts USING btree (segment_id);


--
-- Name: index_segments_on_end_point; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_segments_on_end_point ON public.segments USING gist (end_point);


--
-- Name: index_segments_on_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_segments_on_path ON public.segments USING gist (path);


--
-- Name: index_segments_on_start_point; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_segments_on_start_point ON public.segments USING gist (start_point);


--
-- Name: index_segments_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_segments_on_user_id ON public.segments USING btree (user_id);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_users_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_address ON public.users USING btree (email_address);


--
-- Name: map_privacy_zones fk_rails_03658e8520; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_privacy_zones
    ADD CONSTRAINT fk_rails_03658e8520 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: igpsport_connections fk_rails_1311b1fd21; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.igpsport_connections
    ADD CONSTRAINT fk_rails_1311b1fd21 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: segment_efforts fk_rails_1b0f15ccd5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segment_efforts
    ADD CONSTRAINT fk_rails_1b0f15ccd5 FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: segments fk_rails_3499ac09b5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segments
    ADD CONSTRAINT fk_rails_3499ac09b5 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: gear_defaults fk_rails_403b116a29; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gear_defaults
    ADD CONSTRAINT fk_rails_403b116a29 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: activity_data_points fk_rails_4fe4a431f7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_data_points
    ADD CONSTRAINT fk_rails_4fe4a431f7 FOREIGN KEY (activity_id) REFERENCES public.activities(id);


--
-- Name: segment_efforts fk_rails_5ba8d263cd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segment_efforts
    ADD CONSTRAINT fk_rails_5ba8d263cd FOREIGN KEY (segment_id) REFERENCES public.segments(id) ON DELETE CASCADE;


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: activities fk_rails_7e11bb717f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT fk_rails_7e11bb717f FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: activities fk_rails_88c0317c2b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT fk_rails_88c0317c2b FOREIGN KEY (gear_id) REFERENCES public.gears(id) ON DELETE SET NULL;


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: gear_components fk_rails_9d26c896e8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gear_components
    ADD CONSTRAINT fk_rails_9d26c896e8 FOREIGN KEY (gear_id) REFERENCES public.gears(id) ON DELETE CASCADE;


--
-- Name: gear_defaults fk_rails_a19fd7ac3c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gear_defaults
    ADD CONSTRAINT fk_rails_a19fd7ac3c FOREIGN KEY (gear_id) REFERENCES public.gears(id) ON DELETE CASCADE;


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: best_efforts fk_rails_cbd8dcb843; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.best_efforts
    ADD CONSTRAINT fk_rails_cbd8dcb843 FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: planned_routes fk_rails_dda957683d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planned_routes
    ADD CONSTRAINT fk_rails_dda957683d FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: gears fk_rails_f37d6dac40; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gears
    ADD CONSTRAINT fk_rails_f37d6dac40 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261024150000'),
('20261024140000'),
('20261024130000'),
('20261024120103'),
('20261024120024'),
('20261024120020'),
('20261024100100'),
('20261024100000'),
('20260908120000'),
('20260907190943'),
('20260812183644'),
('20260812183643'),
('20260710142702'),
('20260627124421'),
('20260624173312'),
('20260616120001'),
('20260616120000'),
('20260614120000'),
('20260613120000'),
('20260602120000'),
('20260524203939'),
('20260522120000'),
('20260519202356'),
('20260423203714'),
('20260423203632'),
('20260321155322'),
('20260317204450'),
('20260317203100'),
('20260311185822'),
('20260309202733'),
('20260308200632'),
('20260308200631');

