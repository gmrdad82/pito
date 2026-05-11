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
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: analytics_window; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.analytics_window AS ENUM (
    '7d',
    '28d',
    '90d',
    'lifetime'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    record_id bigint NOT NULL,
    record_type character varying NOT NULL
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
    byte_size bigint NOT NULL,
    checksum character varying,
    content_type character varying,
    created_at timestamp(6) without time zone NOT NULL,
    filename character varying NOT NULL,
    key character varying NOT NULL,
    metadata text,
    service_name character varying NOT NULL
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
-- Name: api_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_tokens (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    expires_at timestamp(6) without time zone,
    last_token_preview character varying NOT NULL,
    last_used_at timestamp(6) without time zone,
    name character varying NOT NULL,
    revoked_at timestamp(6) without time zone,
    scopes jsonb DEFAULT '[]'::jsonb NOT NULL,
    token_digest character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: api_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.api_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.api_tokens_id_seq OWNED BY public.api_tokens.id;


--
-- Name: app_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_settings (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    discord_enabled boolean DEFAULT false NOT NULL,
    key character varying,
    keyboard_navigation_enabled boolean DEFAULT true NOT NULL,
    slack_enabled boolean DEFAULT false NOT NULL,
    timezone character varying DEFAULT 'UTC'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    value text,
    voyage_api_key text,
    voyage_index_project_notes boolean DEFAULT false NOT NULL
);


--
-- Name: app_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.app_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: app_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.app_settings_id_seq OWNED BY public.app_settings.id;


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
-- Name: auth_audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_audit_logs (
    id bigint NOT NULL,
    acting_user_id bigint NOT NULL,
    action integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    source_surface integer NOT NULL,
    target_id bigint NOT NULL,
    target_type character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: auth_audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_audit_logs_id_seq OWNED BY public.auth_audit_logs.id;


--
-- Name: blocked_locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blocked_locations (
    id bigint NOT NULL,
    attempt_count integer DEFAULT 0 NOT NULL,
    blocked_at timestamp(6) without time zone NOT NULL,
    blocked_by_user_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    fingerprint_hash character varying(64) NOT NULL,
    ip_prefix character varying NOT NULL,
    last_attempt_at timestamp(6) without time zone,
    reason text,
    source_surface integer DEFAULT 0 NOT NULL,
    unblocked_at timestamp(6) without time zone,
    unblocked_by_user_id bigint,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: blocked_locations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blocked_locations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blocked_locations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blocked_locations_id_seq OWNED BY public.blocked_locations.id;


--
-- Name: bulk_operation_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bulk_operation_items (
    id bigint NOT NULL,
    bulk_operation_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    error_message text,
    status integer DEFAULT 0 NOT NULL,
    target_id bigint,
    target_type character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint
);


--
-- Name: bulk_operation_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bulk_operation_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bulk_operation_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bulk_operation_items_id_seq OWNED BY public.bulk_operation_items.id;


--
-- Name: bulk_operations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bulk_operations (
    id bigint NOT NULL,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    dry_run_preview jsonb,
    kind integer NOT NULL,
    parameters jsonb,
    started_at timestamp(6) without time zone,
    status integer DEFAULT 0 NOT NULL,
    target_video_ids jsonb,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: bulk_operations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bulk_operations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bulk_operations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bulk_operations_id_seq OWNED BY public.bulk_operations.id;


--
-- Name: bundle_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bundle_members (
    id bigint NOT NULL,
    bundle_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    game_id bigint NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: bundle_members_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bundle_members_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bundle_members_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bundle_members_id_seq OWNED BY public.bundle_members.id;


--
-- Name: bundles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bundles (
    id bigint NOT NULL,
    bundle_type integer DEFAULT 0 NOT NULL,
    composite_cover_checksum character varying,
    composite_cover_path character varying,
    created_at timestamp(6) without time zone NOT NULL,
    igdb_source_id bigint,
    igdb_source_type integer,
    last_error text,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: bundles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bundles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bundles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bundles_id_seq OWNED BY public.bundles.id;


--
-- Name: calendar_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calendar_entries (
    id bigint NOT NULL,
    all_day boolean DEFAULT false NOT NULL,
    channel_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_user_id bigint,
    description text,
    ends_at timestamp(6) without time zone,
    entry_type integer NOT NULL,
    game_id bigint,
    manual_date_override boolean DEFAULT false NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    milestone_rule_id bigint,
    notify_anyway boolean DEFAULT false NOT NULL,
    parent_entry_id bigint,
    project_id bigint,
    release_precision integer,
    source integer DEFAULT 0 NOT NULL,
    source_ref jsonb,
    starts_at timestamp(6) without time zone NOT NULL,
    state integer DEFAULT 0 NOT NULL,
    tba_remind_monthly boolean DEFAULT false NOT NULL,
    timezone character varying DEFAULT 'UTC'::character varying NOT NULL,
    title character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint,
    CONSTRAINT calendar_entries_ends_at_after_starts_at CHECK (((ends_at IS NULL) OR (ends_at >= starts_at)))
);


--
-- Name: calendar_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.calendar_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: calendar_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.calendar_entries_id_seq OWNED BY public.calendar_entries.id;


--
-- Name: channel_change_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_change_logs (
    id bigint NOT NULL,
    changed_at timestamp(6) without time zone NOT NULL,
    changed_by_user_id bigint NOT NULL,
    channel_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    field character varying NOT NULL,
    new_value character varying NOT NULL,
    old_value character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: channel_change_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.channel_change_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channel_change_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.channel_change_logs_id_seq OWNED BY public.channel_change_logs.id;


--
-- Name: channel_dailies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_dailies (
    id bigint NOT NULL,
    ad_impressions bigint,
    average_view_duration numeric(10,2),
    card_clicks bigint DEFAULT 0 NOT NULL,
    card_impressions bigint DEFAULT 0 NOT NULL,
    card_teaser_clicks bigint DEFAULT 0 NOT NULL,
    card_teaser_impressions bigint DEFAULT 0 NOT NULL,
    channel_id bigint NOT NULL,
    comments bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    date date NOT NULL,
    dislikes bigint DEFAULT 0 NOT NULL,
    engaged_views bigint DEFAULT 0 NOT NULL,
    estimated_ad_revenue numeric(12,4),
    estimated_minutes_watched bigint DEFAULT 0 NOT NULL,
    estimated_red_minutes_watched bigint DEFAULT 0 NOT NULL,
    estimated_red_partner_revenue numeric(12,4),
    estimated_revenue numeric(12,4),
    gross_revenue numeric(12,4),
    likes bigint DEFAULT 0 NOT NULL,
    monetized_playbacks bigint,
    red_views bigint DEFAULT 0 NOT NULL,
    shares bigint DEFAULT 0 NOT NULL,
    subscribers_gained bigint DEFAULT 0 NOT NULL,
    subscribers_lost bigint DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_thumbnail_impressions bigint DEFAULT 0 NOT NULL,
    videos_added_to_playlists bigint DEFAULT 0 NOT NULL,
    videos_removed_from_playlists bigint DEFAULT 0 NOT NULL,
    views bigint DEFAULT 0 NOT NULL
);


--
-- Name: channel_dailies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.channel_dailies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channel_dailies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.channel_dailies_id_seq OWNED BY public.channel_dailies.id;


--
-- Name: channel_diffs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_diffs (
    id bigint NOT NULL,
    channel_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    detected_at timestamp(6) without time zone NOT NULL,
    field_diffs jsonb DEFAULT '{}'::jsonb NOT NULL,
    resolution_payload jsonb,
    resolved_at timestamp(6) without time zone,
    resolved_by_user_id bigint,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: channel_diffs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.channel_diffs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channel_diffs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.channel_diffs_id_seq OWNED BY public.channel_diffs.id;


--
-- Name: channel_window_summaries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_window_summaries (
    id bigint NOT NULL,
    ad_impressions bigint,
    average_view_duration numeric(10,2),
    average_view_percentage numeric(10,6),
    card_click_rate numeric(10,6),
    card_clicks bigint DEFAULT 0 NOT NULL,
    card_impressions bigint DEFAULT 0 NOT NULL,
    card_teaser_click_rate numeric(10,6),
    card_teaser_clicks bigint DEFAULT 0 NOT NULL,
    card_teaser_impressions bigint DEFAULT 0 NOT NULL,
    channel_id bigint NOT NULL,
    comments bigint DEFAULT 0 NOT NULL,
    cpm numeric(12,4),
    created_at timestamp(6) without time zone NOT NULL,
    dislikes bigint DEFAULT 0 NOT NULL,
    engaged_views bigint DEFAULT 0 NOT NULL,
    estimated_ad_revenue numeric(12,4),
    estimated_minutes_watched bigint DEFAULT 0 NOT NULL,
    estimated_red_minutes_watched bigint DEFAULT 0 NOT NULL,
    estimated_red_partner_revenue numeric(12,4),
    estimated_revenue numeric(12,4),
    gross_revenue numeric(12,4),
    likes bigint DEFAULT 0 NOT NULL,
    monetized_playbacks bigint,
    playback_based_cpm numeric(12,4),
    red_views bigint DEFAULT 0 NOT NULL,
    shares bigint DEFAULT 0 NOT NULL,
    subscribers_gained bigint DEFAULT 0 NOT NULL,
    subscribers_lost bigint DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_thumbnail_impressions bigint DEFAULT 0 NOT NULL,
    video_thumbnail_impressions_click_rate numeric(10,6),
    videos_added_to_playlists bigint DEFAULT 0 NOT NULL,
    videos_removed_from_playlists bigint DEFAULT 0 NOT NULL,
    views bigint DEFAULT 0 NOT NULL,
    "window" public.analytics_window NOT NULL,
    window_end date NOT NULL,
    window_start date NOT NULL
);


--
-- Name: channel_window_summaries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.channel_window_summaries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channel_window_summaries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.channel_window_summaries_id_seq OWNED BY public.channel_window_summaries.id;


--
-- Name: channels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channels (
    id bigint NOT NULL,
    avatar_url character varying,
    banner_url character varying,
    channel_url character varying NOT NULL,
    country character varying(2),
    created_at timestamp(6) without time zone NOT NULL,
    default_language character varying(10),
    description text,
    handle character varying,
    handle_changed_at timestamp(6) without time zone,
    hidden_subscriber_count boolean DEFAULT false NOT NULL,
    keywords text,
    last_synced_at timestamp(6) without time zone,
    links jsonb DEFAULT '[]'::jsonb NOT NULL,
    published_at timestamp(6) without time zone,
    star boolean DEFAULT false NOT NULL,
    subscriber_count bigint,
    title character varying,
    title_changed_at timestamp(6) without time zone,
    updated_at timestamp(6) without time zone NOT NULL,
    video_count integer,
    view_count bigint,
    watermark_offset_ms integer,
    watermark_timing character varying,
    watermark_url character varying,
    youtube_connection_id bigint
);


--
-- Name: channels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.channels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.channels_id_seq OWNED BY public.channels.id;


--
-- Name: collections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.collections (
    id bigint NOT NULL,
    composite_cover_checksum character varying,
    composite_cover_path character varying,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying DEFAULT 'Untitled collection'::character varying NOT NULL,
    slug character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: collections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.collections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: collections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.collections_id_seq OWNED BY public.collections.id;


--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    igdb_id bigint NOT NULL,
    name character varying NOT NULL,
    slug character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: companies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.companies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: companies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.companies_id_seq OWNED BY public.companies.id;


--
-- Name: footages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.footages (
    id bigint NOT NULL,
    aspect_ratio character varying,
    audio_track_count integer,
    bit_depth integer DEFAULT 8 NOT NULL,
    codec character varying,
    color_profile character varying,
    created_at timestamp(6) without time zone NOT NULL,
    description text,
    duration_seconds integer,
    filename character varying NOT NULL,
    filesize_bytes bigint,
    fps numeric(6,3),
    frames_extracted_at timestamp(6) without time zone,
    game_id bigint,
    has_commentary_track boolean DEFAULT false NOT NULL,
    kind integer NOT NULL,
    local_path character varying NOT NULL,
    nas_path character varying,
    orientation integer,
    platform character varying,
    project_id bigint NOT NULL,
    recorded_at timestamp(6) without time zone,
    resolution character varying,
    source integer NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: footages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.footages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: footages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.footages_id_seq OWNED BY public.footages.id;


--
-- Name: friendly_id_slugs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.friendly_id_slugs (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone,
    scope character varying,
    slug character varying NOT NULL,
    sluggable_id integer NOT NULL,
    sluggable_type character varying(50)
);


--
-- Name: friendly_id_slugs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.friendly_id_slugs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: friendly_id_slugs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.friendly_id_slugs_id_seq OWNED BY public.friendly_id_slugs.id;


--
-- Name: game_developers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_developers (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    game_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: game_developers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.game_developers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: game_developers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.game_developers_id_seq OWNED BY public.game_developers.id;


--
-- Name: game_genres; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_genres (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    game_id bigint NOT NULL,
    genre_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: game_genres_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.game_genres_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: game_genres_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.game_genres_id_seq OWNED BY public.game_genres.id;


--
-- Name: game_platform_ownerships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_platform_ownerships (
    id bigint NOT NULL,
    acquired_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    game_id bigint NOT NULL,
    notes text,
    platform_id bigint NOT NULL,
    store character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: game_platform_ownerships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.game_platform_ownerships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: game_platform_ownerships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.game_platform_ownerships_id_seq OWNED BY public.game_platform_ownerships.id;


--
-- Name: game_platforms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_platforms (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    game_id bigint NOT NULL,
    platform_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: game_platforms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.game_platforms_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: game_platforms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.game_platforms_id_seq OWNED BY public.game_platforms.id;


--
-- Name: game_publishers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_publishers (
    id bigint NOT NULL,
    company_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    game_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: game_publishers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.game_publishers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: game_publishers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.game_publishers_id_seq OWNED BY public.game_publishers.id;


--
-- Name: games; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.games (
    id bigint NOT NULL,
    aggregated_rating numeric(5,2),
    aggregated_rating_count integer,
    collection_id bigint,
    cover_image_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    external_epic_id character varying,
    external_gog_id character varying,
    external_steam_app_id character varying,
    hours_of_footage_cached integer,
    hours_of_footage_manual integer,
    igdb_checksum character varying,
    igdb_id bigint,
    igdb_rating numeric(5,2),
    igdb_rating_count integer,
    igdb_slug character varying,
    igdb_synced_at timestamp(6) without time zone,
    last_sync_error text,
    manual_date_override boolean DEFAULT false NOT NULL,
    notes text,
    platforms jsonb DEFAULT '[]'::jsonb NOT NULL,
    played_at date,
    publisher character varying,
    release_date date,
    release_year integer,
    resyncing boolean DEFAULT false NOT NULL,
    summary text,
    title character varying DEFAULT 'Untitled game'::character varying NOT NULL,
    total_rating numeric(5,2),
    total_rating_count integer,
    ttb_completionist_seconds integer,
    ttb_extras_seconds integer,
    ttb_main_seconds integer,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: games_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.games_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: games_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.games_id_seq OWNED BY public.games.id;


--
-- Name: genres; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.genres (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    igdb_id bigint NOT NULL,
    name character varying NOT NULL,
    slug character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: genres_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.genres_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: genres_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.genres_id_seq OWNED BY public.genres.id;


--
-- Name: import_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_jobs (
    id bigint NOT NULL,
    channel_id bigint NOT NULL,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    enqueued_by_id bigint NOT NULL,
    error_payload jsonb,
    failed_videos integer DEFAULT 0 NOT NULL,
    imported_videos integer DEFAULT 0 NOT NULL,
    started_at timestamp(6) without time zone,
    status integer DEFAULT 0 NOT NULL,
    total_videos integer DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: import_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.import_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.import_jobs_id_seq OWNED BY public.import_jobs.id;


--
-- Name: login_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.login_attempts (
    id bigint NOT NULL,
    approved_by_user_id bigint,
    browser character varying,
    created_at timestamp(6) without time zone NOT NULL,
    email_attempted public.citext,
    fingerprint_hash character varying(64) NOT NULL,
    geo_city character varying,
    geo_country character varying(2),
    geo_region character varying,
    ip inet NOT NULL,
    ip_prefix character varying NOT NULL,
    notification_id bigint,
    os character varying,
    reason integer NOT NULL,
    resolved_at timestamp(6) without time zone,
    result integer NOT NULL,
    session_id bigint,
    updated_at timestamp(6) without time zone NOT NULL,
    user_agent character varying(1024) NOT NULL,
    user_id bigint
);


--
-- Name: login_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.login_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: login_attempts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.login_attempts_id_seq OWNED BY public.login_attempts.id;


--
-- Name: milestone_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.milestone_rules (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_user_id bigint,
    direction integer DEFAULT 0 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    fired_at timestamp(6) without time zone,
    metric character varying NOT NULL,
    metric_window integer DEFAULT 0 NOT NULL,
    name character varying NOT NULL,
    scope_id bigint,
    scope_type integer NOT NULL,
    slug character varying NOT NULL,
    threshold numeric(20,4) NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: milestone_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.milestone_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: milestone_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.milestone_rules_id_seq OWNED BY public.milestone_rules.id;


--
-- Name: notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notes (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    embedding public.vector(1024),
    last_modified_at timestamp(6) without time zone NOT NULL,
    path character varying NOT NULL,
    project_id bigint NOT NULL,
    title character varying DEFAULT 'Untitled note'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    words_count integer DEFAULT 0 NOT NULL
);


--
-- Name: notes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notes_id_seq OWNED BY public.notes.id;


--
-- Name: notification_delivery_channels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_delivery_channels (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    daily_digest boolean DEFAULT false NOT NULL,
    everything boolean DEFAULT false NOT NULL,
    kind character varying NOT NULL,
    last_validated_at timestamp(6) without time zone,
    updated_at timestamp(6) without time zone NOT NULL,
    webhook_url text NOT NULL
);


--
-- Name: notification_delivery_channels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notification_delivery_channels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_delivery_channels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notification_delivery_channels_id_seq OWNED BY public.notification_delivery_channels.id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id bigint NOT NULL,
    body text,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_user_id bigint,
    dedup_key character varying,
    discord_delivered_at timestamp(6) without time zone,
    event_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    event_type character varying NOT NULL,
    fires_at timestamp(6) without time zone NOT NULL,
    in_app_read_at timestamp(6) without time zone,
    kind integer NOT NULL,
    last_error text,
    retry_count integer DEFAULT 0 NOT NULL,
    severity integer DEFAULT 0 NOT NULL,
    slack_delivered_at timestamp(6) without time zone,
    source_calendar_entry_id bigint,
    source_milestone_rule_id bigint,
    title character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    url character varying,
    CONSTRAINT notifications_idempotency_keys_present CHECK (((source_calendar_entry_id IS NOT NULL) OR (dedup_key IS NOT NULL)))
);


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notifications_id_seq OWNED BY public.notifications.id;


--
-- Name: oauth_access_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_access_grants (
    id bigint NOT NULL,
    application_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    expires_in integer NOT NULL,
    redirect_uri text NOT NULL,
    resource_owner_id bigint NOT NULL,
    revoked_at timestamp(6) without time zone,
    scopes character varying DEFAULT ''::character varying NOT NULL,
    token character varying NOT NULL
);


--
-- Name: oauth_access_grants_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_access_grants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_access_grants_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_access_grants_id_seq OWNED BY public.oauth_access_grants.id;


--
-- Name: oauth_access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_access_tokens (
    id bigint NOT NULL,
    application_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    expires_in integer,
    previous_refresh_token character varying DEFAULT ''::character varying NOT NULL,
    refresh_token character varying,
    resource_owner_id bigint,
    revoked_at timestamp(6) without time zone,
    scopes character varying,
    token character varying NOT NULL
);


--
-- Name: oauth_access_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_access_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_access_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_access_tokens_id_seq OWNED BY public.oauth_access_tokens.id;


--
-- Name: oauth_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_applications (
    id bigint NOT NULL,
    confidential boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    redirect_uri text NOT NULL,
    scopes character varying DEFAULT ''::character varying NOT NULL,
    secret character varying NOT NULL,
    uid character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: oauth_applications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_applications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_applications_id_seq OWNED BY public.oauth_applications.id;


--
-- Name: platforms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platforms (
    id bigint NOT NULL,
    abbreviation character varying,
    created_at timestamp(6) without time zone NOT NULL,
    igdb_id bigint,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: platforms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.platforms_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: platforms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.platforms_id_seq OWNED BY public.platforms.id;


--
-- Name: playlist_videos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.playlist_videos (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    playlist_id bigint NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    youtube_playlist_item_id character varying NOT NULL
);


--
-- Name: playlist_videos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.playlist_videos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: playlist_videos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.playlist_videos_id_seq OWNED BY public.playlist_videos.id;


--
-- Name: playlists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.playlists (
    id bigint NOT NULL,
    channel_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    description text,
    item_count integer DEFAULT 0 NOT NULL,
    privacy_status integer,
    published_at timestamp(6) without time zone,
    thumbnail_url character varying,
    title character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    youtube_playlist_id character varying NOT NULL
);


--
-- Name: playlists_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.playlists_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: playlists_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.playlists_id_seq OWNED BY public.playlists.id;


--
-- Name: project_references; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_references (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    project_id bigint NOT NULL,
    referenceable_id bigint NOT NULL,
    referenceable_type character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: project_references_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_references_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_references_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_references_id_seq OWNED BY public.project_references.id;


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.projects (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    footage_duration_seconds integer DEFAULT 0 NOT NULL,
    footages_count integer DEFAULT 0 NOT NULL,
    name character varying DEFAULT 'Untitled project'::character varying NOT NULL,
    notes_count integer DEFAULT 0 NOT NULL,
    notes_words_total integer DEFAULT 0 NOT NULL,
    slug character varying NOT NULL,
    timelines_count integer DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: projects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.projects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: projects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.projects_id_seq OWNED BY public.projects.id;


--
-- Name: rejected_video_imports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rejected_video_imports (
    id bigint NOT NULL,
    channel_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    rejected_at timestamp(6) without time zone NOT NULL,
    rejected_by_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    youtube_video_id character varying NOT NULL
);


--
-- Name: rejected_video_imports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rejected_video_imports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rejected_video_imports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rejected_video_imports_id_seq OWNED BY public.rejected_video_imports.id;


--
-- Name: saved_views; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_views (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    kind integer NOT NULL,
    name character varying NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    url public.citext NOT NULL
);


--
-- Name: saved_views_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.saved_views_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: saved_views_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.saved_views_id_seq OWNED BY public.saved_views.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    approval_required_until timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    ip inet,
    last_activity_at timestamp(6) without time zone,
    remember boolean DEFAULT false NOT NULL,
    revoked_at timestamp(6) without time zone,
    state integer DEFAULT 0 NOT NULL,
    token_digest character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_agent text,
    user_id bigint NOT NULL
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
-- Name: timelines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.timelines (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    duration_seconds integer,
    export_filename character varying,
    fps numeric(6,3),
    project_id bigint NOT NULL,
    resolution character varying,
    state integer DEFAULT 0 NOT NULL,
    title character varying DEFAULT 'Untitled timeline'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint
);


--
-- Name: timelines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.timelines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: timelines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.timelines_id_seq OWNED BY public.timelines.id;


--
-- Name: top_videos_windows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.top_videos_windows (
    id bigint NOT NULL,
    average_view_duration numeric(10,2),
    average_view_percentage numeric(10,6),
    channel_id bigint NOT NULL,
    comments bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    estimated_minutes_watched bigint DEFAULT 0 NOT NULL,
    likes bigint DEFAULT 0 NOT NULL,
    rank integer NOT NULL,
    subscribers_gained bigint DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    views bigint DEFAULT 0 NOT NULL,
    "window" public.analytics_window NOT NULL
);


--
-- Name: top_videos_windows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.top_videos_windows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: top_videos_windows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.top_videos_windows_id_seq OWNED BY public.top_videos_windows.id;


--
-- Name: totp_backup_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.totp_backup_codes (
    id bigint NOT NULL,
    code_digest character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    used_at timestamp(6) without time zone,
    user_id bigint NOT NULL
);


--
-- Name: totp_backup_codes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.totp_backup_codes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: totp_backup_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.totp_backup_codes_id_seq OWNED BY public.totp_backup_codes.id;


--
-- Name: trusted_locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trusted_locations (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    fingerprint_hash character varying(64) NOT NULL,
    first_seen_at timestamp(6) without time zone NOT NULL,
    ip_prefix character varying NOT NULL,
    last_seen_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: trusted_locations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trusted_locations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trusted_locations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trusted_locations_id_seq OWNED BY public.trusted_locations.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    email public.citext NOT NULL,
    last_digest_run_at timestamp(6) without time zone NOT NULL,
    password_digest character varying NOT NULL,
    preferred_games_display_mode integer DEFAULT 0 NOT NULL,
    time_zone character varying DEFAULT 'Etc/UTC'::character varying NOT NULL,
    totp_disabled_at timestamp(6) without time zone,
    totp_enabled_at timestamp(6) without time zone,
    totp_seed_encrypted text,
    updated_at timestamp(6) without time zone NOT NULL
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
-- Name: video_change_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_change_logs (
    id bigint NOT NULL,
    changed_at timestamp(6) without time zone NOT NULL,
    changed_by_user_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    field character varying NOT NULL,
    new_value text,
    old_value text,
    source integer NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL
);


--
-- Name: video_change_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_change_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_change_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_change_logs_id_seq OWNED BY public.video_change_logs.id;


--
-- Name: video_dailies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_dailies (
    id bigint NOT NULL,
    ad_impressions bigint,
    average_view_duration numeric(10,2),
    card_clicks bigint DEFAULT 0 NOT NULL,
    card_impressions bigint DEFAULT 0 NOT NULL,
    card_teaser_clicks bigint DEFAULT 0 NOT NULL,
    card_teaser_impressions bigint DEFAULT 0 NOT NULL,
    comments bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    date date NOT NULL,
    dislikes bigint DEFAULT 0 NOT NULL,
    engaged_views bigint DEFAULT 0 NOT NULL,
    estimated_ad_revenue numeric(12,4),
    estimated_minutes_watched bigint DEFAULT 0 NOT NULL,
    estimated_red_minutes_watched bigint DEFAULT 0 NOT NULL,
    estimated_red_partner_revenue numeric(12,4),
    estimated_revenue numeric(12,4),
    gross_revenue numeric(12,4),
    likes bigint DEFAULT 0 NOT NULL,
    monetized_playbacks bigint,
    red_views bigint DEFAULT 0 NOT NULL,
    shares bigint DEFAULT 0 NOT NULL,
    subscribers_gained bigint DEFAULT 0 NOT NULL,
    subscribers_lost bigint DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    video_thumbnail_impressions bigint DEFAULT 0 NOT NULL,
    videos_added_to_playlists bigint DEFAULT 0 NOT NULL,
    videos_removed_from_playlists bigint DEFAULT 0 NOT NULL,
    views bigint DEFAULT 0 NOT NULL
);


--
-- Name: video_dailies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_dailies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_dailies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_dailies_id_seq OWNED BY public.video_dailies.id;


--
-- Name: video_daily_by_age_group_genders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_daily_by_age_group_genders (
    id bigint NOT NULL,
    age_group text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    date date NOT NULL,
    gender text NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    viewer_percentage numeric(10,6) DEFAULT 0.0 NOT NULL
);


--
-- Name: video_daily_by_age_group_genders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_daily_by_age_group_genders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_daily_by_age_group_genders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_daily_by_age_group_genders_id_seq OWNED BY public.video_daily_by_age_group_genders.id;


--
-- Name: video_daily_by_countries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_daily_by_countries (
    id bigint NOT NULL,
    average_view_duration numeric(10,2),
    average_view_percentage numeric(10,6),
    country_code text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    date date NOT NULL,
    estimated_minutes_watched bigint DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    views bigint DEFAULT 0 NOT NULL
);


--
-- Name: video_daily_by_countries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_daily_by_countries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_daily_by_countries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_daily_by_countries_id_seq OWNED BY public.video_daily_by_countries.id;


--
-- Name: video_daily_by_device_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_daily_by_device_types (
    id bigint NOT NULL,
    average_view_duration numeric(10,2),
    average_view_percentage numeric(10,6),
    created_at timestamp(6) without time zone NOT NULL,
    date date NOT NULL,
    device_type text NOT NULL,
    estimated_minutes_watched bigint DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    views bigint DEFAULT 0 NOT NULL
);


--
-- Name: video_daily_by_device_types_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_daily_by_device_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_daily_by_device_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_daily_by_device_types_id_seq OWNED BY public.video_daily_by_device_types.id;


--
-- Name: video_daily_by_operating_systems; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_daily_by_operating_systems (
    id bigint NOT NULL,
    average_view_duration numeric(10,2),
    average_view_percentage numeric(10,6),
    created_at timestamp(6) without time zone NOT NULL,
    date date NOT NULL,
    estimated_minutes_watched bigint DEFAULT 0 NOT NULL,
    operating_system text NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    views bigint DEFAULT 0 NOT NULL
);


--
-- Name: video_daily_by_operating_systems_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_daily_by_operating_systems_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_daily_by_operating_systems_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_daily_by_operating_systems_id_seq OWNED BY public.video_daily_by_operating_systems.id;


--
-- Name: video_daily_by_subscribed_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_daily_by_subscribed_statuses (
    id bigint NOT NULL,
    average_view_percentage numeric(10,6),
    created_at timestamp(6) without time zone NOT NULL,
    date date NOT NULL,
    estimated_minutes_watched bigint DEFAULT 0 NOT NULL,
    subscribed_status text NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    views bigint DEFAULT 0 NOT NULL
);


--
-- Name: video_daily_by_subscribed_statuses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_daily_by_subscribed_statuses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_daily_by_subscribed_statuses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_daily_by_subscribed_statuses_id_seq OWNED BY public.video_daily_by_subscribed_statuses.id;


--
-- Name: video_daily_by_traffic_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_daily_by_traffic_sources (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    date date NOT NULL,
    estimated_minutes_watched bigint DEFAULT 0 NOT NULL,
    traffic_source_type text NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    video_thumbnail_impressions bigint DEFAULT 0 NOT NULL,
    video_thumbnail_impressions_click_rate numeric(10,6),
    views bigint DEFAULT 0 NOT NULL
);


--
-- Name: video_daily_by_traffic_sources_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_daily_by_traffic_sources_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_daily_by_traffic_sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_daily_by_traffic_sources_id_seq OWNED BY public.video_daily_by_traffic_sources.id;


--
-- Name: video_diffs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_diffs (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    detected_at timestamp(6) without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    resolution_payload jsonb,
    resolved_at timestamp(6) without time zone,
    resolved_by_user_id bigint,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL
);


--
-- Name: video_diffs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_diffs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_diffs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_diffs_id_seq OWNED BY public.video_diffs.id;


--
-- Name: video_game_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_game_links (
    id bigint NOT NULL,
    bundle_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_user_id bigint,
    game_id bigint,
    is_primary boolean DEFAULT false NOT NULL,
    link_type integer NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    CONSTRAINT video_game_links_exactly_one_target CHECK ((((link_type = 0) AND (game_id IS NOT NULL) AND (bundle_id IS NULL)) OR ((link_type = 1) AND (bundle_id IS NOT NULL) AND (game_id IS NULL))))
);


--
-- Name: video_game_links_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_game_links_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_game_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_game_links_id_seq OWNED BY public.video_game_links.id;


--
-- Name: video_retentions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_retentions (
    id bigint NOT NULL,
    audience_watch_ratio numeric(10,6),
    computed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    elapsed_ratio_bucket numeric(5,4) NOT NULL,
    relative_retention_performance numeric(10,6),
    started_watching bigint DEFAULT 0 NOT NULL,
    stopped_watching bigint DEFAULT 0 NOT NULL,
    total_segment_impressions bigint DEFAULT 0 NOT NULL,
    video_id bigint NOT NULL
);


--
-- Name: video_retentions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_retentions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_retentions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_retentions_id_seq OWNED BY public.video_retentions.id;


--
-- Name: video_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_stats (
    id bigint NOT NULL,
    average_view_duration_seconds double precision,
    average_view_percentage double precision,
    comments integer,
    created_at timestamp(6) without time zone NOT NULL,
    date date,
    likes integer,
    shares integer,
    subscribers_gained integer,
    subscribers_lost integer,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    views integer,
    watch_time_minutes double precision
);


--
-- Name: video_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_stats_id_seq OWNED BY public.video_stats.id;


--
-- Name: video_uploads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_uploads (
    id bigint NOT NULL,
    bytes_sent bigint DEFAULT 0 NOT NULL,
    channel_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    description text,
    error_message text,
    file_name character varying NOT NULL,
    file_size bigint NOT NULL,
    privacy_status integer DEFAULT 0,
    resumable_uri character varying,
    status integer DEFAULT 0 NOT NULL,
    title character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint,
    youtube_video_id character varying
);


--
-- Name: video_uploads_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_uploads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_uploads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_uploads_id_seq OWNED BY public.video_uploads.id;


--
-- Name: video_viewer_time_buckets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_viewer_time_buckets (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    day_of_week_utc integer NOT NULL,
    hour_of_day_utc integer NOT NULL,
    last_synced_at timestamp(6) without time zone,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    view_count integer DEFAULT 0 NOT NULL,
    watch_time_seconds bigint DEFAULT 0 NOT NULL,
    CONSTRAINT viewer_time_buckets_dow_range CHECK (((day_of_week_utc >= 0) AND (day_of_week_utc <= 6))),
    CONSTRAINT viewer_time_buckets_hour_range CHECK (((hour_of_day_utc >= 0) AND (hour_of_day_utc <= 23))),
    CONSTRAINT viewer_time_buckets_view_count_nonneg CHECK ((view_count >= 0)),
    CONSTRAINT viewer_time_buckets_watch_time_nonneg CHECK ((watch_time_seconds >= 0))
);


--
-- Name: video_viewer_time_buckets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_viewer_time_buckets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_viewer_time_buckets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_viewer_time_buckets_id_seq OWNED BY public.video_viewer_time_buckets.id;


--
-- Name: video_window_summaries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_window_summaries (
    id bigint NOT NULL,
    ad_impressions bigint,
    average_view_duration numeric(10,2),
    average_view_percentage numeric(10,6),
    card_click_rate numeric(10,6),
    card_clicks bigint DEFAULT 0 NOT NULL,
    card_impressions bigint DEFAULT 0 NOT NULL,
    card_teaser_click_rate numeric(10,6),
    card_teaser_clicks bigint DEFAULT 0 NOT NULL,
    card_teaser_impressions bigint DEFAULT 0 NOT NULL,
    comments bigint DEFAULT 0 NOT NULL,
    cpm numeric(12,4),
    created_at timestamp(6) without time zone NOT NULL,
    dislikes bigint DEFAULT 0 NOT NULL,
    engaged_views bigint DEFAULT 0 NOT NULL,
    estimated_ad_revenue numeric(12,4),
    estimated_minutes_watched bigint DEFAULT 0 NOT NULL,
    estimated_red_minutes_watched bigint DEFAULT 0 NOT NULL,
    estimated_red_partner_revenue numeric(12,4),
    estimated_revenue numeric(12,4),
    gross_revenue numeric(12,4),
    likes bigint DEFAULT 0 NOT NULL,
    monetized_playbacks bigint,
    playback_based_cpm numeric(12,4),
    red_views bigint DEFAULT 0 NOT NULL,
    shares bigint DEFAULT 0 NOT NULL,
    subscribers_gained bigint DEFAULT 0 NOT NULL,
    subscribers_lost bigint DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_id bigint NOT NULL,
    video_thumbnail_impressions bigint DEFAULT 0 NOT NULL,
    video_thumbnail_impressions_click_rate numeric(10,6),
    videos_added_to_playlists bigint DEFAULT 0 NOT NULL,
    videos_removed_from_playlists bigint DEFAULT 0 NOT NULL,
    views bigint DEFAULT 0 NOT NULL,
    "window" public.analytics_window NOT NULL,
    window_end date NOT NULL,
    window_start date NOT NULL
);


--
-- Name: video_window_summaries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_window_summaries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_window_summaries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_window_summaries_id_seq OWNED BY public.video_window_summaries.id;


--
-- Name: videos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.videos (
    id bigint NOT NULL,
    category_id character varying,
    channel_id bigint NOT NULL,
    comment_count bigint DEFAULT 0 NOT NULL,
    contains_synthetic_media boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    description text,
    duration_seconds integer,
    embeddable boolean DEFAULT true NOT NULL,
    etag character varying,
    last_diff_checked_at timestamp(6) without time zone,
    last_sync_error text,
    last_synced_at timestamp(6) without time zone,
    like_count bigint DEFAULT 0 NOT NULL,
    made_for_kids_effective boolean DEFAULT false NOT NULL,
    pre_publish_age_ok boolean DEFAULT false NOT NULL,
    pre_publish_checked_at timestamp(6) without time zone,
    pre_publish_end_screen_ok boolean DEFAULT false NOT NULL,
    pre_publish_game_ok boolean DEFAULT false NOT NULL,
    pre_publish_paid_promotion_ok boolean DEFAULT false NOT NULL,
    privacy_status integer DEFAULT 0 NOT NULL,
    project_id bigint,
    public_stats_viewable boolean DEFAULT true NOT NULL,
    publish_at timestamp(6) without time zone,
    published_at timestamp(6) without time zone,
    self_declared_made_for_kids boolean DEFAULT false NOT NULL,
    star boolean DEFAULT false NOT NULL,
    tags jsonb DEFAULT '[]'::jsonb NOT NULL,
    thumbnail_url character varying,
    title character varying(100) DEFAULT ''::character varying NOT NULL,
    title_changed_at timestamp(6) without time zone,
    updated_at timestamp(6) without time zone NOT NULL,
    view_count bigint DEFAULT 0 NOT NULL,
    youtube_connection_id bigint,
    youtube_video_id character varying
);


--
-- Name: videos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.videos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: videos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.videos_id_seq OWNED BY public.videos.id;


--
-- Name: youtube_api_calls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.youtube_api_calls (
    id bigint NOT NULL,
    client_kind character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    duration_ms integer,
    endpoint character varying NOT NULL,
    error_message text,
    http_method character varying NOT NULL,
    http_status integer,
    outcome character varying NOT NULL,
    units integer NOT NULL,
    user_id bigint,
    youtube_connection_id bigint
);


--
-- Name: youtube_api_calls_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.youtube_api_calls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: youtube_api_calls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.youtube_api_calls_id_seq OWNED BY public.youtube_api_calls.id;


--
-- Name: youtube_connections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.youtube_connections (
    id bigint NOT NULL,
    access_token text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    email public.citext NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    google_subject_id character varying NOT NULL,
    last_authorized_at timestamp(6) without time zone NOT NULL,
    last_refreshed_at timestamp(6) without time zone,
    needs_reauth boolean DEFAULT false NOT NULL,
    refresh_token text,
    scopes jsonb DEFAULT '[]'::jsonb NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: youtube_connections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.youtube_connections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: youtube_connections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.youtube_connections_id_seq OWNED BY public.youtube_connections.id;


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
-- Name: api_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_tokens ALTER COLUMN id SET DEFAULT nextval('public.api_tokens_id_seq'::regclass);


--
-- Name: app_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_settings ALTER COLUMN id SET DEFAULT nextval('public.app_settings_id_seq'::regclass);


--
-- Name: auth_audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_audit_logs ALTER COLUMN id SET DEFAULT nextval('public.auth_audit_logs_id_seq'::regclass);


--
-- Name: blocked_locations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_locations ALTER COLUMN id SET DEFAULT nextval('public.blocked_locations_id_seq'::regclass);


--
-- Name: bulk_operation_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_operation_items ALTER COLUMN id SET DEFAULT nextval('public.bulk_operation_items_id_seq'::regclass);


--
-- Name: bulk_operations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_operations ALTER COLUMN id SET DEFAULT nextval('public.bulk_operations_id_seq'::regclass);


--
-- Name: bundle_members id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bundle_members ALTER COLUMN id SET DEFAULT nextval('public.bundle_members_id_seq'::regclass);


--
-- Name: bundles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bundles ALTER COLUMN id SET DEFAULT nextval('public.bundles_id_seq'::regclass);


--
-- Name: calendar_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_entries ALTER COLUMN id SET DEFAULT nextval('public.calendar_entries_id_seq'::regclass);


--
-- Name: channel_change_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_change_logs ALTER COLUMN id SET DEFAULT nextval('public.channel_change_logs_id_seq'::regclass);


--
-- Name: channel_dailies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_dailies ALTER COLUMN id SET DEFAULT nextval('public.channel_dailies_id_seq'::regclass);


--
-- Name: channel_diffs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_diffs ALTER COLUMN id SET DEFAULT nextval('public.channel_diffs_id_seq'::regclass);


--
-- Name: channel_window_summaries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_window_summaries ALTER COLUMN id SET DEFAULT nextval('public.channel_window_summaries_id_seq'::regclass);


--
-- Name: channels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels ALTER COLUMN id SET DEFAULT nextval('public.channels_id_seq'::regclass);


--
-- Name: collections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collections ALTER COLUMN id SET DEFAULT nextval('public.collections_id_seq'::regclass);


--
-- Name: companies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies ALTER COLUMN id SET DEFAULT nextval('public.companies_id_seq'::regclass);


--
-- Name: footages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footages ALTER COLUMN id SET DEFAULT nextval('public.footages_id_seq'::regclass);


--
-- Name: friendly_id_slugs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendly_id_slugs ALTER COLUMN id SET DEFAULT nextval('public.friendly_id_slugs_id_seq'::regclass);


--
-- Name: game_developers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_developers ALTER COLUMN id SET DEFAULT nextval('public.game_developers_id_seq'::regclass);


--
-- Name: game_genres id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_genres ALTER COLUMN id SET DEFAULT nextval('public.game_genres_id_seq'::regclass);


--
-- Name: game_platform_ownerships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_platform_ownerships ALTER COLUMN id SET DEFAULT nextval('public.game_platform_ownerships_id_seq'::regclass);


--
-- Name: game_platforms id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_platforms ALTER COLUMN id SET DEFAULT nextval('public.game_platforms_id_seq'::regclass);


--
-- Name: game_publishers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_publishers ALTER COLUMN id SET DEFAULT nextval('public.game_publishers_id_seq'::regclass);


--
-- Name: games id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games ALTER COLUMN id SET DEFAULT nextval('public.games_id_seq'::regclass);


--
-- Name: genres id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.genres ALTER COLUMN id SET DEFAULT nextval('public.genres_id_seq'::regclass);


--
-- Name: import_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs ALTER COLUMN id SET DEFAULT nextval('public.import_jobs_id_seq'::regclass);


--
-- Name: login_attempts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_attempts ALTER COLUMN id SET DEFAULT nextval('public.login_attempts_id_seq'::regclass);


--
-- Name: milestone_rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.milestone_rules ALTER COLUMN id SET DEFAULT nextval('public.milestone_rules_id_seq'::regclass);


--
-- Name: notes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notes ALTER COLUMN id SET DEFAULT nextval('public.notes_id_seq'::regclass);


--
-- Name: notification_delivery_channels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_delivery_channels ALTER COLUMN id SET DEFAULT nextval('public.notification_delivery_channels_id_seq'::regclass);


--
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications ALTER COLUMN id SET DEFAULT nextval('public.notifications_id_seq'::regclass);


--
-- Name: oauth_access_grants id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants ALTER COLUMN id SET DEFAULT nextval('public.oauth_access_grants_id_seq'::regclass);


--
-- Name: oauth_access_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens ALTER COLUMN id SET DEFAULT nextval('public.oauth_access_tokens_id_seq'::regclass);


--
-- Name: oauth_applications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_applications ALTER COLUMN id SET DEFAULT nextval('public.oauth_applications_id_seq'::regclass);


--
-- Name: platforms id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platforms ALTER COLUMN id SET DEFAULT nextval('public.platforms_id_seq'::regclass);


--
-- Name: playlist_videos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlist_videos ALTER COLUMN id SET DEFAULT nextval('public.playlist_videos_id_seq'::regclass);


--
-- Name: playlists id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlists ALTER COLUMN id SET DEFAULT nextval('public.playlists_id_seq'::regclass);


--
-- Name: project_references id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_references ALTER COLUMN id SET DEFAULT nextval('public.project_references_id_seq'::regclass);


--
-- Name: projects id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects ALTER COLUMN id SET DEFAULT nextval('public.projects_id_seq'::regclass);


--
-- Name: rejected_video_imports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rejected_video_imports ALTER COLUMN id SET DEFAULT nextval('public.rejected_video_imports_id_seq'::regclass);


--
-- Name: saved_views id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_views ALTER COLUMN id SET DEFAULT nextval('public.saved_views_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: timelines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timelines ALTER COLUMN id SET DEFAULT nextval('public.timelines_id_seq'::regclass);


--
-- Name: top_videos_windows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.top_videos_windows ALTER COLUMN id SET DEFAULT nextval('public.top_videos_windows_id_seq'::regclass);


--
-- Name: totp_backup_codes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.totp_backup_codes ALTER COLUMN id SET DEFAULT nextval('public.totp_backup_codes_id_seq'::regclass);


--
-- Name: trusted_locations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trusted_locations ALTER COLUMN id SET DEFAULT nextval('public.trusted_locations_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: video_change_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_change_logs ALTER COLUMN id SET DEFAULT nextval('public.video_change_logs_id_seq'::regclass);


--
-- Name: video_dailies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_dailies ALTER COLUMN id SET DEFAULT nextval('public.video_dailies_id_seq'::regclass);


--
-- Name: video_daily_by_age_group_genders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_daily_by_age_group_genders ALTER COLUMN id SET DEFAULT nextval('public.video_daily_by_age_group_genders_id_seq'::regclass);


--
-- Name: video_daily_by_countries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_daily_by_countries ALTER COLUMN id SET DEFAULT nextval('public.video_daily_by_countries_id_seq'::regclass);


--
-- Name: video_daily_by_device_types id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_daily_by_device_types ALTER COLUMN id SET DEFAULT nextval('public.video_daily_by_device_types_id_seq'::regclass);


--
-- Name: video_daily_by_operating_systems id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_daily_by_operating_systems ALTER COLUMN id SET DEFAULT nextval('public.video_daily_by_operating_systems_id_seq'::regclass);


--
-- Name: video_daily_by_subscribed_statuses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_daily_by_subscribed_statuses ALTER COLUMN id SET DEFAULT nextval('public.video_daily_by_subscribed_statuses_id_seq'::regclass);


--
-- Name: video_daily_by_traffic_sources id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_daily_by_traffic_sources ALTER COLUMN id SET DEFAULT nextval('public.video_daily_by_traffic_sources_id_seq'::regclass);


--
-- Name: video_diffs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_diffs ALTER COLUMN id SET DEFAULT nextval('public.video_diffs_id_seq'::regclass);


--
-- Name: video_game_links id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_game_links ALTER COLUMN id SET DEFAULT nextval('public.video_game_links_id_seq'::regclass);


--
-- Name: video_retentions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_retentions ALTER COLUMN id SET DEFAULT nextval('public.video_retentions_id_seq'::regclass);


--
-- Name: video_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_stats ALTER COLUMN id SET DEFAULT nextval('public.video_stats_id_seq'::regclass);


--
-- Name: video_uploads id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_uploads ALTER COLUMN id SET DEFAULT nextval('public.video_uploads_id_seq'::regclass);


--
-- Name: video_viewer_time_buckets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_viewer_time_buckets ALTER COLUMN id SET DEFAULT nextval('public.video_viewer_time_buckets_id_seq'::regclass);


--
-- Name: video_window_summaries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_window_summaries ALTER COLUMN id SET DEFAULT nextval('public.video_window_summaries_id_seq'::regclass);


--
-- Name: videos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.videos ALTER COLUMN id SET DEFAULT nextval('public.videos_id_seq'::regclass);


--
-- Name: youtube_api_calls id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.youtube_api_calls ALTER COLUMN id SET DEFAULT nextval('public.youtube_api_calls_id_seq'::regclass);


--
-- Name: youtube_connections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.youtube_connections ALTER COLUMN id SET DEFAULT nextval('public.youtube_connections_id_seq'::regclass);


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
-- Name: api_tokens api_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_tokens
    ADD CONSTRAINT api_tokens_pkey PRIMARY KEY (id);


--
-- Name: app_settings app_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_settings
    ADD CONSTRAINT app_settings_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: auth_audit_logs auth_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_audit_logs
    ADD CONSTRAINT auth_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: blocked_locations blocked_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_locations
    ADD CONSTRAINT blocked_locations_pkey PRIMARY KEY (id);


--
-- Name: bulk_operation_items bulk_operation_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_operation_items
    ADD CONSTRAINT bulk_operation_items_pkey PRIMARY KEY (id);


--
-- Name: bulk_operations bulk_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_operations
    ADD CONSTRAINT bulk_operations_pkey PRIMARY KEY (id);


--
-- Name: bundle_members bundle_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bundle_members
    ADD CONSTRAINT bundle_members_pkey PRIMARY KEY (id);


--
-- Name: bundles bundles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bundles
    ADD CONSTRAINT bundles_pkey PRIMARY KEY (id);


--
-- Name: calendar_entries calendar_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_entries
    ADD CONSTRAINT calendar_entries_pkey PRIMARY KEY (id);


--
-- Name: channel_change_logs channel_change_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_change_logs
    ADD CONSTRAINT channel_change_logs_pkey PRIMARY KEY (id);


--
-- Name: channel_dailies channel_dailies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_dailies
    ADD CONSTRAINT channel_dailies_pkey PRIMARY KEY (id);


--
-- Name: channel_diffs channel_diffs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_diffs
    ADD CONSTRAINT channel_diffs_pkey PRIMARY KEY (id);


--
-- Name: channel_window_summaries channel_window_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_window_summaries
    ADD CONSTRAINT channel_window_summaries_pkey PRIMARY KEY (id);


--
-- Name: channels channels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT channels_pkey PRIMARY KEY (id);


--
-- Name: collections collections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collections
    ADD CONSTRAINT collections_pkey PRIMARY KEY (id);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: footages footages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footages
    ADD CONSTRAINT footages_pkey PRIMARY KEY (id);


--
-- Name: friendly_id_slugs friendly_id_slugs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendly_id_slugs
    ADD CONSTRAINT friendly_id_slugs_pkey PRIMARY KEY (id);


--
-- Name: game_developers game_developers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_developers
    ADD CONSTRAINT game_developers_pkey PRIMARY KEY (id);


--
-- Name: game_genres game_genres_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_genres
    ADD CONSTRAINT game_genres_pkey PRIMARY KEY (id);


--
-- Name: game_platform_ownerships game_platform_ownerships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_platform_ownerships
    ADD CONSTRAINT game_platform_ownerships_pkey PRIMARY KEY (id);


--
-- Name: game_platforms game_platforms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_platforms
    ADD CONSTRAINT game_platforms_pkey PRIMARY KEY (id);


--
-- Name: game_publishers game_publishers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_publishers
    ADD CONSTRAINT game_publishers_pkey PRIMARY KEY (id);


--
-- Name: games games_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_pkey PRIMARY KEY (id);


--
-- Name: genres genres_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.genres
    ADD CONSTRAINT genres_pkey PRIMARY KEY (id);


--
-- Name: import_jobs import_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_pkey PRIMARY KEY (id);


--
-- Name: login_attempts login_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_attempts
    ADD CONSTRAINT login_attempts_pkey PRIMARY KEY (id);


--
-- Name: milestone_rules milestone_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.milestone_rules
    ADD CONSTRAINT milestone_rules_pkey PRIMARY KEY (id);


--
-- Name: notes notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT notes_pkey PRIMARY KEY (id);


--
-- Name: notification_delivery_channels notification_delivery_channels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_delivery_channels
    ADD CONSTRAINT notification_delivery_channels_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_grants oauth_access_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants
    ADD CONSTRAINT oauth_access_grants_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_tokens oauth_access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT oauth_access_tokens_pkey PRIMARY KEY (id);


--
-- Name: oauth_applications oauth_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_applications
    ADD CONSTRAINT oauth_applications_pkey PRIMARY KEY (id);


--
-- Name: platforms platforms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platforms
    ADD CONSTRAINT platforms_pkey PRIMARY KEY (id);


--
-- Name: playlist_videos playlist_videos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlist_videos
    ADD CONSTRAINT playlist_videos_pkey PRIMARY KEY (id);


--
-- Name: playlists playlists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlists
    ADD CONSTRAINT playlists_pkey PRIMARY KEY (id);


--
-- Name: project_references project_references_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_references
    ADD CONSTRAINT project_references_pkey PRIMARY KEY (id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: rejected_video_imports rejected_video_imports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rejected_video_imports
    ADD CONSTRAINT rejected_video_imports_pkey PRIMARY KEY (id);


--
-- Name: saved_views saved_views_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_views
    ADD CONSTRAINT saved_views_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: timelines timelines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timelines
    ADD CONSTRAINT timelines_pkey PRIMARY KEY (id);


--
-- Name: top_videos_windows top_videos_windows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.top_videos_windows
    ADD CONSTRAINT top_videos_windows_pkey PRIMARY KEY (id);


--
-- Name: totp_backup_codes totp_backup_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.totp_backup_codes
    ADD CONSTRAINT totp_backup_codes_pkey PRIMARY KEY (id);


--
-- Name: trusted_locations trusted_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trusted_locations
    ADD CONSTRAINT trusted_locations_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: video_change_logs video_change_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_change_logs
    ADD CONSTRAINT video_change_logs_pkey PRIMARY KEY (id);


--
-- Name: video_dailies video_dailies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_dailies
    ADD CONSTRAINT video_dailies_pkey PRIMARY KEY (id);


--
-- Name: video_daily_by_age_group_genders video_daily_by_age_group_genders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_daily_by_age_group_genders
    ADD CONSTRAINT video_daily_by_age_group_genders_pkey PRIMARY KEY (id);


--
-- Name: video_daily_by_countries video_daily_by_countries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_daily_by_countries
    ADD CONSTRAINT video_daily_by_countries_pkey PRIMARY KEY (id);


--
-- Name: video_daily_by_device_types video_daily_by_device_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_daily_by_device_types
    ADD CONSTRAINT video_daily_by_device_types_pkey PRIMARY KEY (id);


--
-- Name: video_daily_by_operating_systems video_daily_by_operating_systems_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_daily_by_operating_systems
    ADD CONSTRAINT video_daily_by_operating_systems_pkey PRIMARY KEY (id);


--
-- Name: video_daily_by_subscribed_statuses video_daily_by_subscribed_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_daily_by_subscribed_statuses
    ADD CONSTRAINT video_daily_by_subscribed_statuses_pkey PRIMARY KEY (id);


--
-- Name: video_daily_by_traffic_sources video_daily_by_traffic_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_daily_by_traffic_sources
    ADD CONSTRAINT video_daily_by_traffic_sources_pkey PRIMARY KEY (id);


--
-- Name: video_diffs video_diffs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_diffs
    ADD CONSTRAINT video_diffs_pkey PRIMARY KEY (id);


--
-- Name: video_game_links video_game_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_game_links
    ADD CONSTRAINT video_game_links_pkey PRIMARY KEY (id);


--
-- Name: video_retentions video_retentions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_retentions
    ADD CONSTRAINT video_retentions_pkey PRIMARY KEY (id);


--
-- Name: video_stats video_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_stats
    ADD CONSTRAINT video_stats_pkey PRIMARY KEY (id);


--
-- Name: video_uploads video_uploads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_uploads
    ADD CONSTRAINT video_uploads_pkey PRIMARY KEY (id);


--
-- Name: video_viewer_time_buckets video_viewer_time_buckets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_viewer_time_buckets
    ADD CONSTRAINT video_viewer_time_buckets_pkey PRIMARY KEY (id);


--
-- Name: video_window_summaries video_window_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_window_summaries
    ADD CONSTRAINT video_window_summaries_pkey PRIMARY KEY (id);


--
-- Name: videos videos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.videos
    ADD CONSTRAINT videos_pkey PRIMARY KEY (id);


--
-- Name: youtube_api_calls youtube_api_calls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.youtube_api_calls
    ADD CONSTRAINT youtube_api_calls_pkey PRIMARY KEY (id);


--
-- Name: youtube_connections youtube_connections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.youtube_connections
    ADD CONSTRAINT youtube_connections_pkey PRIMARY KEY (id);


--
-- Name: idx_channel_window_summary_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_channel_window_summary_uniq ON public.channel_window_summaries USING btree (channel_id, "window");


--
-- Name: idx_top_videos_window_rank_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_top_videos_window_rank_uniq ON public.top_videos_windows USING btree (channel_id, "window", rank);


--
-- Name: idx_top_videos_window_video_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_top_videos_window_video_uniq ON public.top_videos_windows USING btree (channel_id, "window", video_id);


--
-- Name: idx_video_daily_by_age_gender_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_video_daily_by_age_gender_uniq ON public.video_daily_by_age_group_genders USING btree (video_id, date, age_group, gender);


--
-- Name: idx_video_daily_by_country_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_video_daily_by_country_uniq ON public.video_daily_by_countries USING btree (video_id, date, country_code);


--
-- Name: idx_video_daily_by_device_type_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_video_daily_by_device_type_uniq ON public.video_daily_by_device_types USING btree (video_id, date, device_type);


--
-- Name: idx_video_daily_by_os_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_video_daily_by_os_uniq ON public.video_daily_by_operating_systems USING btree (video_id, date, operating_system);


--
-- Name: idx_video_daily_by_subscribed_status_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_video_daily_by_subscribed_status_uniq ON public.video_daily_by_subscribed_statuses USING btree (video_id, date, subscribed_status);


--
-- Name: idx_video_daily_by_traffic_source_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_video_daily_by_traffic_source_uniq ON public.video_daily_by_traffic_sources USING btree (video_id, date, traffic_source_type);


--
-- Name: idx_video_game_links_primary; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_video_game_links_primary ON public.video_game_links USING btree (is_primary) WHERE (is_primary = true);


--
-- Name: idx_video_game_links_unique_bundle; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_video_game_links_unique_bundle ON public.video_game_links USING btree (video_id, bundle_id) WHERE (bundle_id IS NOT NULL);


--
-- Name: idx_video_game_links_unique_game; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_video_game_links_unique_game ON public.video_game_links USING btree (video_id, game_id) WHERE (game_id IS NOT NULL);


--
-- Name: idx_video_retention_bucket_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_video_retention_bucket_uniq ON public.video_retentions USING btree (video_id, elapsed_ratio_bucket);


--
-- Name: idx_video_window_summary_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_video_window_summary_uniq ON public.video_window_summaries USING btree (video_id, "window");


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
-- Name: index_api_tokens_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_tokens_on_expires_at ON public.api_tokens USING btree (expires_at);


--
-- Name: index_api_tokens_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_tokens_on_token_digest ON public.api_tokens USING btree (token_digest);


--
-- Name: index_api_tokens_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_tokens_on_user_id ON public.api_tokens USING btree (user_id);


--
-- Name: index_app_settings_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_app_settings_on_key ON public.app_settings USING btree (key);


--
-- Name: index_auth_audit_logs_on_acting_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_auth_audit_logs_on_acting_user_id ON public.auth_audit_logs USING btree (acting_user_id);


--
-- Name: index_auth_audit_logs_on_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_auth_audit_logs_on_action ON public.auth_audit_logs USING btree (action);


--
-- Name: index_auth_audit_logs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_auth_audit_logs_on_created_at ON public.auth_audit_logs USING btree (created_at);


--
-- Name: index_auth_audit_logs_on_source_surface; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_auth_audit_logs_on_source_surface ON public.auth_audit_logs USING btree (source_surface);


--
-- Name: index_auth_audit_logs_on_target_type_and_target_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_auth_audit_logs_on_target_type_and_target_id ON public.auth_audit_logs USING btree (target_type, target_id);


--
-- Name: index_blocked_locations_on_blocked_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_blocked_locations_on_blocked_by_user_id ON public.blocked_locations USING btree (blocked_by_user_id);


--
-- Name: index_blocked_locations_on_unblocked_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_blocked_locations_on_unblocked_at ON public.blocked_locations USING btree (unblocked_at);


--
-- Name: index_blocked_locations_unique_pair; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_blocked_locations_unique_pair ON public.blocked_locations USING btree (fingerprint_hash, ip_prefix);


--
-- Name: index_bulk_operation_items_on_bulk_operation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bulk_operation_items_on_bulk_operation_id ON public.bulk_operation_items USING btree (bulk_operation_id);


--
-- Name: index_bulk_operation_items_on_bulk_operation_id_and_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_bulk_operation_items_on_bulk_operation_id_and_video_id ON public.bulk_operation_items USING btree (bulk_operation_id, video_id);


--
-- Name: index_bulk_operation_items_on_target_type_and_target_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bulk_operation_items_on_target_type_and_target_id ON public.bulk_operation_items USING btree (target_type, target_id);


--
-- Name: index_bulk_operation_items_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bulk_operation_items_on_video_id ON public.bulk_operation_items USING btree (video_id);


--
-- Name: index_bundle_members_on_bundle_and_game; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_bundle_members_on_bundle_and_game ON public.bundle_members USING btree (bundle_id, game_id);


--
-- Name: index_bundle_members_on_bundle_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bundle_members_on_bundle_and_position ON public.bundle_members USING btree (bundle_id, "position");


--
-- Name: index_bundle_members_on_bundle_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bundle_members_on_bundle_id ON public.bundle_members USING btree (bundle_id);


--
-- Name: index_bundle_members_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bundle_members_on_game_id ON public.bundle_members USING btree (game_id);


--
-- Name: index_bundles_on_bundle_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bundles_on_bundle_type ON public.bundles USING btree (bundle_type);


--
-- Name: index_bundles_on_igdb_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bundles_on_igdb_source_id ON public.bundles USING btree (igdb_source_id) WHERE (igdb_source_id IS NOT NULL);


--
-- Name: index_bundles_on_igdb_source_pair; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_bundles_on_igdb_source_pair ON public.bundles USING btree (igdb_source_type, igdb_source_id) WHERE ((igdb_source_type IS NOT NULL) AND (igdb_source_id IS NOT NULL));


--
-- Name: index_bundles_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_bundles_on_slug ON public.bundles USING btree (slug);


--
-- Name: index_calendar_entries_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_channel_id ON public.calendar_entries USING btree (channel_id) WHERE (channel_id IS NOT NULL);


--
-- Name: index_calendar_entries_on_created_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_created_by_user_id ON public.calendar_entries USING btree (created_by_user_id) WHERE (created_by_user_id IS NOT NULL);


--
-- Name: index_calendar_entries_on_ends_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_ends_at ON public.calendar_entries USING btree (ends_at) WHERE (ends_at IS NOT NULL);


--
-- Name: index_calendar_entries_on_entry_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_entry_type ON public.calendar_entries USING btree (entry_type);


--
-- Name: index_calendar_entries_on_entry_type_and_starts_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_entry_type_and_starts_at ON public.calendar_entries USING btree (entry_type, starts_at);


--
-- Name: index_calendar_entries_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_game_id ON public.calendar_entries USING btree (game_id) WHERE (game_id IS NOT NULL);


--
-- Name: index_calendar_entries_on_metadata; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_metadata ON public.calendar_entries USING gin (metadata);


--
-- Name: index_calendar_entries_on_milestone_rule_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_milestone_rule_id ON public.calendar_entries USING btree (milestone_rule_id) WHERE (milestone_rule_id IS NOT NULL);


--
-- Name: index_calendar_entries_on_parent_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_parent_entry_id ON public.calendar_entries USING btree (parent_entry_id) WHERE (parent_entry_id IS NOT NULL);


--
-- Name: index_calendar_entries_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_project_id ON public.calendar_entries USING btree (project_id) WHERE (project_id IS NOT NULL);


--
-- Name: index_calendar_entries_on_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_source ON public.calendar_entries USING btree (source);


--
-- Name: index_calendar_entries_on_source_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_source_ref ON public.calendar_entries USING gin (source_ref) WHERE (source_ref IS NOT NULL);


--
-- Name: index_calendar_entries_on_starts_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_starts_at ON public.calendar_entries USING btree (starts_at);


--
-- Name: index_calendar_entries_on_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_state ON public.calendar_entries USING btree (state);


--
-- Name: index_calendar_entries_on_state_and_starts_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_state_and_starts_at ON public.calendar_entries USING btree (state, starts_at);


--
-- Name: index_calendar_entries_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_entries_on_video_id ON public.calendar_entries USING btree (video_id) WHERE (video_id IS NOT NULL);


--
-- Name: index_calendar_entries_unique_channel_source_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_calendar_entries_unique_channel_source_ref ON public.calendar_entries USING btree (entry_type, ((source_ref ->> 'channel_id'::text))) WHERE ((entry_type = 0) AND (source_ref IS NOT NULL));


--
-- Name: index_calendar_entries_unique_game_source_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_calendar_entries_unique_game_source_ref ON public.calendar_entries USING btree (entry_type, ((source_ref ->> 'game_id'::text))) WHERE ((entry_type = 3) AND (source_ref IS NOT NULL));


--
-- Name: index_calendar_entries_unique_milestone_rule; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_calendar_entries_unique_milestone_rule ON public.calendar_entries USING btree (milestone_rule_id) WHERE ((entry_type = 6) AND (source = 2));


--
-- Name: index_calendar_entries_unique_video_source_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_calendar_entries_unique_video_source_ref ON public.calendar_entries USING btree (entry_type, ((source_ref ->> 'video_id'::text))) WHERE ((entry_type = ANY (ARRAY[1, 2])) AND (source_ref IS NOT NULL));


--
-- Name: index_channel_change_logs_on_changed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channel_change_logs_on_changed_at ON public.channel_change_logs USING btree (changed_at);


--
-- Name: index_channel_change_logs_on_changed_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channel_change_logs_on_changed_by_user_id ON public.channel_change_logs USING btree (changed_by_user_id);


--
-- Name: index_channel_change_logs_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channel_change_logs_on_channel_id ON public.channel_change_logs USING btree (channel_id);


--
-- Name: index_channel_dailies_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channel_dailies_on_channel_id ON public.channel_dailies USING btree (channel_id);


--
-- Name: index_channel_dailies_on_channel_id_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_channel_dailies_on_channel_id_and_date ON public.channel_dailies USING btree (channel_id, date);


--
-- Name: index_channel_dailies_on_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channel_dailies_on_date ON public.channel_dailies USING btree (date);


--
-- Name: index_channel_diffs_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channel_diffs_on_channel_id ON public.channel_diffs USING btree (channel_id);


--
-- Name: index_channel_diffs_on_resolved_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channel_diffs_on_resolved_at ON public.channel_diffs USING btree (resolved_at);


--
-- Name: index_channel_diffs_on_resolved_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channel_diffs_on_resolved_by_user_id ON public.channel_diffs USING btree (resolved_by_user_id);


--
-- Name: index_channel_diffs_open_per_channel; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_channel_diffs_open_per_channel ON public.channel_diffs USING btree (channel_id) WHERE (resolved_at IS NULL);


--
-- Name: index_channel_window_summaries_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channel_window_summaries_on_channel_id ON public.channel_window_summaries USING btree (channel_id);


--
-- Name: index_channels_on_channel_url; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_channels_on_channel_url ON public.channels USING btree (channel_url);


--
-- Name: index_channels_on_handle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channels_on_handle ON public.channels USING btree (handle) WHERE (handle IS NOT NULL);


--
-- Name: index_channels_on_last_synced_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channels_on_last_synced_at ON public.channels USING btree (last_synced_at);


--
-- Name: index_channels_on_youtube_connection_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channels_on_youtube_connection_id ON public.channels USING btree (youtube_connection_id);


--
-- Name: index_collections_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_collections_on_name ON public.collections USING btree (name);


--
-- Name: index_collections_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_collections_on_slug ON public.collections USING btree (slug);


--
-- Name: index_companies_on_igdb_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_companies_on_igdb_id ON public.companies USING btree (igdb_id);


--
-- Name: index_footages_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_footages_on_game_id ON public.footages USING btree (game_id);


--
-- Name: index_footages_on_local_path; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_footages_on_local_path ON public.footages USING btree (local_path);


--
-- Name: index_footages_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_footages_on_project_id ON public.footages USING btree (project_id);


--
-- Name: index_friendly_id_slugs_on_slug_and_sluggable_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_friendly_id_slugs_on_slug_and_sluggable_type ON public.friendly_id_slugs USING btree (slug, sluggable_type);


--
-- Name: index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope ON public.friendly_id_slugs USING btree (slug, sluggable_type, scope);


--
-- Name: index_friendly_id_slugs_on_sluggable_type_and_sluggable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_friendly_id_slugs_on_sluggable_type_and_sluggable_id ON public.friendly_id_slugs USING btree (sluggable_type, sluggable_id);


--
-- Name: index_game_developers_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_developers_on_company_id ON public.game_developers USING btree (company_id);


--
-- Name: index_game_developers_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_developers_on_game_id ON public.game_developers USING btree (game_id);


--
-- Name: index_game_developers_on_game_id_and_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_game_developers_on_game_id_and_company_id ON public.game_developers USING btree (game_id, company_id);


--
-- Name: index_game_genres_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_genres_on_game_id ON public.game_genres USING btree (game_id);


--
-- Name: index_game_genres_on_game_id_and_genre_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_game_genres_on_game_id_and_genre_id ON public.game_genres USING btree (game_id, genre_id);


--
-- Name: index_game_genres_on_genre_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_genres_on_genre_id ON public.game_genres USING btree (genre_id);


--
-- Name: index_game_platform_ownerships_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_platform_ownerships_on_game_id ON public.game_platform_ownerships USING btree (game_id);


--
-- Name: index_game_platform_ownerships_on_platform_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_platform_ownerships_on_platform_id ON public.game_platform_ownerships USING btree (platform_id);


--
-- Name: index_game_platform_ownerships_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_game_platform_ownerships_uniqueness ON public.game_platform_ownerships USING btree (game_id, platform_id);


--
-- Name: index_game_platforms_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_platforms_on_game_id ON public.game_platforms USING btree (game_id);


--
-- Name: index_game_platforms_on_game_id_and_platform_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_game_platforms_on_game_id_and_platform_id ON public.game_platforms USING btree (game_id, platform_id);


--
-- Name: index_game_platforms_on_platform_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_platforms_on_platform_id ON public.game_platforms USING btree (platform_id);


--
-- Name: index_game_publishers_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_publishers_on_company_id ON public.game_publishers USING btree (company_id);


--
-- Name: index_game_publishers_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_publishers_on_game_id ON public.game_publishers USING btree (game_id);


--
-- Name: index_game_publishers_on_game_id_and_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_game_publishers_on_game_id_and_company_id ON public.game_publishers USING btree (game_id, company_id);


--
-- Name: index_games_on_collection_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_games_on_collection_id ON public.games USING btree (collection_id);


--
-- Name: index_games_on_external_steam_app_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_games_on_external_steam_app_id ON public.games USING btree (external_steam_app_id) WHERE (external_steam_app_id IS NOT NULL);


--
-- Name: index_games_on_igdb_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_games_on_igdb_id ON public.games USING btree (igdb_id) WHERE (igdb_id IS NOT NULL);


--
-- Name: index_games_on_igdb_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_games_on_igdb_slug ON public.games USING btree (igdb_slug) WHERE (igdb_slug IS NOT NULL);


--
-- Name: index_games_on_igdb_synced_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_games_on_igdb_synced_at ON public.games USING btree (igdb_synced_at);


--
-- Name: index_games_on_release_year; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_games_on_release_year ON public.games USING btree (release_year);


--
-- Name: index_games_on_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_games_on_title ON public.games USING btree (title);


--
-- Name: index_genres_on_igdb_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_genres_on_igdb_id ON public.genres USING btree (igdb_id);


--
-- Name: index_import_jobs_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_jobs_on_channel_id ON public.import_jobs USING btree (channel_id);


--
-- Name: index_import_jobs_on_channel_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_jobs_on_channel_id_and_status ON public.import_jobs USING btree (channel_id, status);


--
-- Name: index_import_jobs_on_enqueued_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_jobs_on_enqueued_by_id ON public.import_jobs USING btree (enqueued_by_id);


--
-- Name: index_import_jobs_on_status_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_jobs_on_status_and_created_at ON public.import_jobs USING btree (status, created_at);


--
-- Name: index_login_attempts_on_approved_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_login_attempts_on_approved_by_user_id ON public.login_attempts USING btree (approved_by_user_id);


--
-- Name: index_login_attempts_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_login_attempts_on_created_at ON public.login_attempts USING btree (created_at);


--
-- Name: index_login_attempts_on_email_attempted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_login_attempts_on_email_attempted ON public.login_attempts USING btree (email_attempted);


--
-- Name: index_login_attempts_on_fingerprint_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_login_attempts_on_fingerprint_hash ON public.login_attempts USING btree (fingerprint_hash);


--
-- Name: index_login_attempts_on_fp_and_prefix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_login_attempts_on_fp_and_prefix ON public.login_attempts USING btree (fingerprint_hash, ip_prefix);


--
-- Name: index_login_attempts_on_notification_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_login_attempts_on_notification_id ON public.login_attempts USING btree (notification_id);


--
-- Name: index_login_attempts_on_result; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_login_attempts_on_result ON public.login_attempts USING btree (result);


--
-- Name: index_login_attempts_on_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_login_attempts_on_session_id ON public.login_attempts USING btree (session_id);


--
-- Name: index_login_attempts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_login_attempts_on_user_id ON public.login_attempts USING btree (user_id);


--
-- Name: index_milestone_rules_on_created_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_milestone_rules_on_created_by_user_id ON public.milestone_rules USING btree (created_by_user_id) WHERE (created_by_user_id IS NOT NULL);


--
-- Name: index_milestone_rules_on_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_milestone_rules_on_enabled ON public.milestone_rules USING btree (enabled);


--
-- Name: index_milestone_rules_on_fired_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_milestone_rules_on_fired_at ON public.milestone_rules USING btree (fired_at);


--
-- Name: index_milestone_rules_on_metric; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_milestone_rules_on_metric ON public.milestone_rules USING btree (metric);


--
-- Name: index_milestone_rules_on_scope_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_milestone_rules_on_scope_id ON public.milestone_rules USING btree (scope_id) WHERE (scope_id IS NOT NULL);


--
-- Name: index_milestone_rules_on_scope_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_milestone_rules_on_scope_type ON public.milestone_rules USING btree (scope_type);


--
-- Name: index_milestone_rules_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_milestone_rules_on_slug ON public.milestone_rules USING btree (slug);


--
-- Name: index_notes_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notes_on_project_id ON public.notes USING btree (project_id);


--
-- Name: index_notes_on_project_id_and_path; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_notes_on_project_id_and_path ON public.notes USING btree (project_id, path);


--
-- Name: index_notification_delivery_channels_on_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_notification_delivery_channels_on_kind ON public.notification_delivery_channels USING btree (kind);


--
-- Name: index_notifications_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_created_at ON public.notifications USING btree (created_at);


--
-- Name: index_notifications_on_created_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_created_by_user_id ON public.notifications USING btree (created_by_user_id) WHERE (created_by_user_id IS NOT NULL);


--
-- Name: index_notifications_on_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_event_type ON public.notifications USING btree (event_type);


--
-- Name: index_notifications_on_fires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_fires_at ON public.notifications USING btree (fires_at);


--
-- Name: index_notifications_on_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_kind ON public.notifications USING btree (kind);


--
-- Name: index_notifications_on_read_state_and_recency; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_read_state_and_recency ON public.notifications USING btree (in_app_read_at, created_at);


--
-- Name: index_notifications_on_severity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_severity ON public.notifications USING btree (severity);


--
-- Name: index_notifications_on_source_calendar_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_source_calendar_entry_id ON public.notifications USING btree (source_calendar_entry_id) WHERE (source_calendar_entry_id IS NOT NULL);


--
-- Name: index_notifications_on_source_milestone_rule_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_source_milestone_rule_id ON public.notifications USING btree (source_milestone_rule_id) WHERE (source_milestone_rule_id IS NOT NULL);


--
-- Name: index_notifications_on_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_unread ON public.notifications USING btree (in_app_read_at) WHERE (in_app_read_at IS NULL);


--
-- Name: index_notifications_unique_calendar_event; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_notifications_unique_calendar_event ON public.notifications USING btree (event_type, source_calendar_entry_id, fires_at) WHERE (source_calendar_entry_id IS NOT NULL);


--
-- Name: index_notifications_unique_dedup; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_notifications_unique_dedup ON public.notifications USING btree (event_type, dedup_key) WHERE (dedup_key IS NOT NULL);


--
-- Name: index_oauth_access_grants_on_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_grants_on_application_id ON public.oauth_access_grants USING btree (application_id);


--
-- Name: index_oauth_access_grants_on_resource_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_grants_on_resource_owner_id ON public.oauth_access_grants USING btree (resource_owner_id);


--
-- Name: index_oauth_access_grants_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_grants_on_token ON public.oauth_access_grants USING btree (token);


--
-- Name: index_oauth_access_tokens_on_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_tokens_on_application_id ON public.oauth_access_tokens USING btree (application_id);


--
-- Name: index_oauth_access_tokens_on_refresh_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_tokens_on_refresh_token ON public.oauth_access_tokens USING btree (refresh_token);


--
-- Name: index_oauth_access_tokens_on_resource_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_tokens_on_resource_owner_id ON public.oauth_access_tokens USING btree (resource_owner_id);


--
-- Name: index_oauth_access_tokens_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_tokens_on_token ON public.oauth_access_tokens USING btree (token);


--
-- Name: index_oauth_applications_on_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_applications_on_uid ON public.oauth_applications USING btree (uid);


--
-- Name: index_platforms_on_igdb_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_platforms_on_igdb_id ON public.platforms USING btree (igdb_id);


--
-- Name: index_platforms_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_platforms_on_slug ON public.platforms USING btree (slug);


--
-- Name: index_playlist_videos_on_playlist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_playlist_videos_on_playlist_id ON public.playlist_videos USING btree (playlist_id);


--
-- Name: index_playlist_videos_on_playlist_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_playlist_videos_on_playlist_id_and_position ON public.playlist_videos USING btree (playlist_id, "position");


--
-- Name: index_playlist_videos_on_playlist_id_and_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_playlist_videos_on_playlist_id_and_video_id ON public.playlist_videos USING btree (playlist_id, video_id);


--
-- Name: index_playlist_videos_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_playlist_videos_on_video_id ON public.playlist_videos USING btree (video_id);


--
-- Name: index_playlist_videos_on_youtube_playlist_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_playlist_videos_on_youtube_playlist_item_id ON public.playlist_videos USING btree (youtube_playlist_item_id);


--
-- Name: index_playlists_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_playlists_on_channel_id ON public.playlists USING btree (channel_id);


--
-- Name: index_playlists_on_youtube_playlist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_playlists_on_youtube_playlist_id ON public.playlists USING btree (youtube_playlist_id);


--
-- Name: index_project_references_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_references_on_project_id ON public.project_references USING btree (project_id);


--
-- Name: index_project_references_on_referenceable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_references_on_referenceable ON public.project_references USING btree (referenceable_type, referenceable_id);


--
-- Name: index_project_references_unique_per_project; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_project_references_unique_per_project ON public.project_references USING btree (project_id, referenceable_type, referenceable_id);


--
-- Name: index_projects_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_name ON public.projects USING btree (name);


--
-- Name: index_projects_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_projects_on_slug ON public.projects USING btree (slug);


--
-- Name: index_rejected_video_imports_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rejected_video_imports_on_channel_id ON public.rejected_video_imports USING btree (channel_id);


--
-- Name: index_rejected_video_imports_on_rejected_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_rejected_video_imports_on_rejected_by_id ON public.rejected_video_imports USING btree (rejected_by_id);


--
-- Name: index_rejected_video_imports_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_rejected_video_imports_unique ON public.rejected_video_imports USING btree (channel_id, youtube_video_id);


--
-- Name: index_saved_views_on_kind_and_url; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_saved_views_on_kind_and_url ON public.saved_views USING btree (kind, url);


--
-- Name: index_sessions_on_approval_required_until; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_approval_required_until ON public.sessions USING btree (approval_required_until);


--
-- Name: index_sessions_on_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_state ON public.sessions USING btree (state);


--
-- Name: index_sessions_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sessions_on_token_digest ON public.sessions USING btree (token_digest);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_timelines_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_timelines_on_project_id ON public.timelines USING btree (project_id);


--
-- Name: index_timelines_on_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_timelines_on_state ON public.timelines USING btree (state);


--
-- Name: index_timelines_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_timelines_on_video_id ON public.timelines USING btree (video_id);


--
-- Name: index_top_videos_windows_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_top_videos_windows_on_channel_id ON public.top_videos_windows USING btree (channel_id);


--
-- Name: index_top_videos_windows_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_top_videos_windows_on_video_id ON public.top_videos_windows USING btree (video_id);


--
-- Name: index_totp_backup_codes_on_used_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_totp_backup_codes_on_used_at ON public.totp_backup_codes USING btree (used_at);


--
-- Name: index_totp_backup_codes_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_totp_backup_codes_on_user_id ON public.totp_backup_codes USING btree (user_id);


--
-- Name: index_trusted_locations_on_last_seen_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trusted_locations_on_last_seen_at ON public.trusted_locations USING btree (last_seen_at);


--
-- Name: index_trusted_locations_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trusted_locations_on_user_id ON public.trusted_locations USING btree (user_id);


--
-- Name: index_trusted_locations_unique_triple; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_trusted_locations_unique_triple ON public.trusted_locations USING btree (user_id, fingerprint_hash, ip_prefix);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_last_digest_run_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_last_digest_run_at ON public.users USING btree (last_digest_run_at);


--
-- Name: index_video_change_logs_on_changed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_change_logs_on_changed_at ON public.video_change_logs USING btree (changed_at);


--
-- Name: index_video_change_logs_on_changed_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_change_logs_on_changed_by_user_id ON public.video_change_logs USING btree (changed_by_user_id);


--
-- Name: index_video_change_logs_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_change_logs_on_video_id ON public.video_change_logs USING btree (video_id);


--
-- Name: index_video_dailies_on_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_dailies_on_date ON public.video_dailies USING btree (date);


--
-- Name: index_video_dailies_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_dailies_on_video_id ON public.video_dailies USING btree (video_id);


--
-- Name: index_video_dailies_on_video_id_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_video_dailies_on_video_id_and_date ON public.video_dailies USING btree (video_id, date);


--
-- Name: index_video_daily_by_age_group_genders_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_daily_by_age_group_genders_on_video_id ON public.video_daily_by_age_group_genders USING btree (video_id);


--
-- Name: index_video_daily_by_countries_on_country_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_daily_by_countries_on_country_code ON public.video_daily_by_countries USING btree (country_code);


--
-- Name: index_video_daily_by_countries_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_daily_by_countries_on_video_id ON public.video_daily_by_countries USING btree (video_id);


--
-- Name: index_video_daily_by_device_types_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_daily_by_device_types_on_video_id ON public.video_daily_by_device_types USING btree (video_id);


--
-- Name: index_video_daily_by_operating_systems_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_daily_by_operating_systems_on_video_id ON public.video_daily_by_operating_systems USING btree (video_id);


--
-- Name: index_video_daily_by_subscribed_statuses_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_daily_by_subscribed_statuses_on_video_id ON public.video_daily_by_subscribed_statuses USING btree (video_id);


--
-- Name: index_video_daily_by_traffic_sources_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_daily_by_traffic_sources_on_video_id ON public.video_daily_by_traffic_sources USING btree (video_id);


--
-- Name: index_video_diffs_on_resolved_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_diffs_on_resolved_at ON public.video_diffs USING btree (resolved_at);


--
-- Name: index_video_diffs_on_resolved_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_diffs_on_resolved_by_user_id ON public.video_diffs USING btree (resolved_by_user_id);


--
-- Name: index_video_diffs_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_diffs_on_video_id ON public.video_diffs USING btree (video_id);


--
-- Name: index_video_diffs_open_per_video; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_video_diffs_open_per_video ON public.video_diffs USING btree (video_id) WHERE (resolved_at IS NULL);


--
-- Name: index_video_game_links_on_bundle_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_game_links_on_bundle_id ON public.video_game_links USING btree (bundle_id);


--
-- Name: index_video_game_links_on_created_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_game_links_on_created_by_user_id ON public.video_game_links USING btree (created_by_user_id);


--
-- Name: index_video_game_links_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_game_links_on_game_id ON public.video_game_links USING btree (game_id);


--
-- Name: index_video_game_links_on_link_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_game_links_on_link_type ON public.video_game_links USING btree (link_type);


--
-- Name: index_video_game_links_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_game_links_on_video_id ON public.video_game_links USING btree (video_id);


--
-- Name: index_video_retentions_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_retentions_on_video_id ON public.video_retentions USING btree (video_id);


--
-- Name: index_video_stats_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_stats_on_video_id ON public.video_stats USING btree (video_id);


--
-- Name: index_video_stats_on_video_id_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_video_stats_on_video_id_and_date ON public.video_stats USING btree (video_id, date);


--
-- Name: index_video_uploads_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_uploads_on_channel_id ON public.video_uploads USING btree (channel_id);


--
-- Name: index_video_uploads_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_uploads_on_video_id ON public.video_uploads USING btree (video_id);


--
-- Name: index_video_viewer_time_buckets_on_last_synced_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_viewer_time_buckets_on_last_synced_at ON public.video_viewer_time_buckets USING btree (last_synced_at);


--
-- Name: index_video_window_summaries_on_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_window_summaries_on_video_id ON public.video_window_summaries USING btree (video_id);


--
-- Name: index_videos_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_videos_on_channel_id ON public.videos USING btree (channel_id);


--
-- Name: index_videos_on_privacy_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_videos_on_privacy_status ON public.videos USING btree (privacy_status);


--
-- Name: index_videos_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_videos_on_project_id ON public.videos USING btree (project_id);


--
-- Name: index_videos_on_publish_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_videos_on_publish_at ON public.videos USING btree (publish_at) WHERE (publish_at IS NOT NULL);


--
-- Name: index_videos_on_published_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_videos_on_published_at ON public.videos USING btree (published_at);


--
-- Name: index_videos_on_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_videos_on_tags ON public.videos USING gin (tags);


--
-- Name: index_videos_on_youtube_connection_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_videos_on_youtube_connection_id ON public.videos USING btree (youtube_connection_id);


--
-- Name: index_videos_on_youtube_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_videos_on_youtube_video_id ON public.videos USING btree (youtube_video_id);


--
-- Name: index_viewer_time_buckets_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_viewer_time_buckets_uniq ON public.video_viewer_time_buckets USING btree (video_id, day_of_week_utc, hour_of_day_utc);


--
-- Name: index_youtube_api_calls_on_connection_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_youtube_api_calls_on_connection_time ON public.youtube_api_calls USING btree (youtube_connection_id, created_at);


--
-- Name: index_youtube_api_calls_on_kind_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_youtube_api_calls_on_kind_time ON public.youtube_api_calls USING btree (client_kind, created_at);


--
-- Name: index_youtube_api_calls_on_outcome_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_youtube_api_calls_on_outcome_time ON public.youtube_api_calls USING btree (outcome, created_at);


--
-- Name: index_youtube_api_calls_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_youtube_api_calls_on_user_id ON public.youtube_api_calls USING btree (user_id);


--
-- Name: index_youtube_api_calls_on_youtube_connection_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_youtube_api_calls_on_youtube_connection_id ON public.youtube_api_calls USING btree (youtube_connection_id);


--
-- Name: index_youtube_connections_on_google_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_youtube_connections_on_google_subject_id ON public.youtube_connections USING btree (google_subject_id);


--
-- Name: index_youtube_connections_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_youtube_connections_on_user_id ON public.youtube_connections USING btree (user_id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: bulk_operation_items fk_rails_f44a488493; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bulk_operation_items
    ADD CONSTRAINT fk_rails_f44a488493 FOREIGN KEY (bulk_operation_id) REFERENCES public.bulk_operations(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260511160500'),
('20260511160358'),
('20260511160101'),
('20260511160100'),
('20260511160003'),
('20260511160002'),
('20260511160001'),
('20260511160000'),
('20260511155924'),
('20260511150000'),
('20260511143000'),
('20260511140001'),
('20260511140000'),
('20260511132718'),
('20260511120002'),
('20260511120001'),
('20260511120000'),
('20260511024709'),
('20260511021258'),
('20260511021257'),
('20260511021256'),
('20260511021200'),
('20260511021116'),
('20260511021100'),
('20260510210002'),
('20260510210001'),
('20260510210000'),
('20260510192747'),
('20260510192746'),
('20260510192745'),
('20260510192744'),
('20260510192743'),
('20260510192742'),
('20260510190000'),
('20260510183815'),
('20260510180000'),
('20260510170001'),
('20260510170000'),
('20260510160000'),
('20260510155554'),
('20260510140002'),
('20260510140001'),
('20260510140000'),
('20260510135730'),
('20260510120003'),
('20260510120002'),
('20260510120001'),
('20260510120000'),
('20260510110333'),
('20260510081047'),
('20260510021811'),
('20260507400003'),
('20260507400002'),
('20260507400001'),
('20260507400000'),
('20260507300004'),
('20260507300003'),
('20260507300002'),
('20260507300001'),
('20260507300000'),
('20260507200001'),
('20260507200000'),
('20260507100002'),
('20260507100001'),
('20260507000090'),
('20260507000082'),
('20260507000081'),
('20260507000080'),
('20260507000072'),
('20260507000071'),
('20260507000070'),
('20260507000062'),
('20260507000061'),
('20260507000060'),
('20260507000052'),
('20260507000051'),
('20260507000050'),
('20260507000042'),
('20260507000041'),
('20260507000040'),
('20260507000032'),
('20260507000031'),
('20260507000030'),
('20260507000022'),
('20260507000021'),
('20260507000020'),
('20260507000012'),
('20260507000011'),
('20260507000010'),
('20260507000001'),
('20260506105253'),
('20260506105252'),
('20260506011259'),
('20260506011258'),
('20260506011257'),
('20260506000001'),
('20260505213857'),
('20260504233708'),
('20260504000012'),
('20260504000011'),
('20260504000010'),
('20260504000009'),
('20260504000008'),
('20260504000007'),
('20260504000006'),
('20260504000005'),
('20260504000004'),
('20260504000003'),
('20260504000002'),
('20260504000001'),
('20260501220626'),
('20260501220625'),
('20260501220624'),
('20260501165846'),
('20260501165845'),
('20260428151207'),
('20260427021551'),
('20260426223653'),
('20260426222647'),
('20260426222642'),
('20260426222411'),
('20260426221958'),
('20260426221952'),
('20260426221542'),
('20260426221118'),
('20260426213600'),
('20260426151250'),
('20260426150334'),
('20260426150324'),
('20260426150313'),
('20260426150307'),
('20260426150302'),
('20260426150254');

