--
-- PostgreSQL database dump
--

\restrict RulEVreLDOunijRdFkF9qi6o2Zvh5ecoEDdn3Bwv9OgrDQjzklVAOFBfcKpHe33

-- Dumped from database version 16.11 (Ubuntu 16.11-1.pgdg24.04+1)
-- Dumped by pg_dump version 16.11 (Ubuntu 16.11-1.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: aayush
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO aayush;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: aayush
--

COMMENT ON SCHEMA public IS 'Agentless Lab Resource Monitoring Database - Network Discovery Based';


--
-- Name: timescaledb; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public;


--
-- Name: EXTENSION timescaledb; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION timescaledb IS 'Enables scalable inserts and complex queries for time-series data (Community Edition)';


--
-- Name: timescaledb_toolkit; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit WITH SCHEMA public;


--
-- Name: EXTENSION timescaledb_toolkit; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION timescaledb_toolkit IS 'Library of analytical hyperfunctions, time-series pipelining, and other SQL utilities';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: count_active_systems_by_dept(); Type: FUNCTION; Schema: public; Owner: aayush
--

CREATE FUNCTION public.count_active_systems_by_dept() RETURNS TABLE(dept_name character varying, active_count bigint, total_count bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.dept_name,
        COUNT(s.system_id) FILTER (WHERE s.status = 'active'),
        COUNT(s.system_id)
    FROM departments d
    LEFT JOIN systems s USING(dept_id)
    GROUP BY d.dept_name
    ORDER BY d.dept_name;
END;
$$;


ALTER FUNCTION public.count_active_systems_by_dept() OWNER TO aayush;

--
-- Name: detect_disk_io_anomaly(); Type: FUNCTION; Schema: public; Owner: aayush
--

CREATE FUNCTION public.detect_disk_io_anomaly() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.disk_write_mbps > 500 THEN
        INSERT INTO maintainence_logs (
            system_id,
            severity,
            message
        )
        VALUES (
            NEW.system_id,
            'warning',
            'Abnormally high disk write throughput detected'
        );
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.detect_disk_io_anomaly() OWNER TO aayush;

--
-- Name: detect_sustained_cpu_overload(); Type: FUNCTION; Schema: public; Owner: aayush
--

CREATE FUNCTION public.detect_sustained_cpu_overload() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    high_cpu_minutes INT;
BEGIN
    SELECT COUNT(*) INTO high_cpu_minutes
    FROM metrics
    WHERE system_id = NEW.system_id
      AND cpu_percent > 85
      AND timestamp >= NOW() - INTERVAL '5 minutes';

    IF high_cpu_minutes >= 5 THEN
        INSERT INTO maintainence_logs (
            system_id,
            severity,
            message
        )
        VALUES (
            NEW.system_id,
            'critical',
            'Sustained CPU usage above 85% for over 5 minutes'
        );
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.detect_sustained_cpu_overload() OWNER TO aayush;

--
-- Name: get_systems_in_subnet(text); Type: FUNCTION; Schema: public; Owner: aayush
--

CREATE FUNCTION public.get_systems_in_subnet(subnet_cidr text) RETURNS TABLE(system_id integer, hostname character varying, ip_address text, status character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.system_id,
        s.hostname,
        s.ip_address::TEXT,
        s.status
    FROM systems s
    WHERE s.ip_address <<= subnet_cidr::INET
    ORDER BY s.ip_address;
END;
$$;


ALTER FUNCTION public.get_systems_in_subnet(subnet_cidr text) OWNER TO aayush;

--
-- Name: mark_systems_offline(); Type: FUNCTION; Schema: public; Owner: aayush
--

CREATE FUNCTION public.mark_systems_offline() RETURNS TABLE(system_id integer, hostname character varying, old_status character varying, new_status character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    UPDATE systems s
    SET status = 'offline', updated_at = NOW()
    FROM (
        SELECT sys.system_id, sys.hostname, sys.status as old_status
        FROM systems sys
        LEFT JOIN (
            SELECT m.system_id, MAX(m.timestamp) as last_metric_time
            FROM metrics m
            GROUP BY m.system_id
        ) recent_metrics ON sys.system_id = recent_metrics.system_id
        WHERE sys.status NOT IN ('maintenance')
        AND (
            recent_metrics.last_metric_time IS NULL 
            OR recent_metrics.last_metric_time < NOW() - INTERVAL '10 minutes'
        )
        AND sys.status != 'offline'
    ) offline_systems
    WHERE s.system_id = offline_systems.system_id
    RETURNING s.system_id, s.hostname, offline_systems.old_status, s.status as new_status;
END;
$$;


ALTER FUNCTION public.mark_systems_offline() OWNER TO aayush;

--
-- Name: FUNCTION mark_systems_offline(); Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON FUNCTION public.mark_systems_offline() IS 'Marks systems as offline if no metrics received in last 10 minutes. Should be run periodically (every 5-10 minutes). Does not affect systems in maintenance mode.';


--
-- Name: update_system_status(); Type: FUNCTION; Schema: public; Owner: aayush
--

CREATE FUNCTION public.update_system_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only update status if not in maintenance
    IF (SELECT status FROM systems WHERE system_id = NEW.system_id) != 'maintenance' THEN
        UPDATE systems 
        SET status = 'active', updated_at = NOW()
        WHERE system_id = NEW.system_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_system_status() OWNER TO aayush;

--
-- Name: FUNCTION update_system_status(); Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON FUNCTION public.update_system_status() IS 'Automatically updates system status to active when metrics are received, unless system is in maintenance mode';


--
-- Name: update_updated_at(); Type: FUNCTION; Schema: public; Owner: aayush
--

CREATE FUNCTION public.update_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_at() OWNER TO aayush;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: _compressed_hypertable_14; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._compressed_hypertable_14 (
);


ALTER TABLE _timescaledb_internal._compressed_hypertable_14 OWNER TO aayush;

--
-- Name: metrics; Type: TABLE; Schema: public; Owner: aayush
--

CREATE TABLE public.metrics (
    metric_id bigint NOT NULL,
    system_id integer NOT NULL,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    cpu_percent numeric(5,2),
    cpu_temperature numeric(5,2),
    ram_percent numeric(5,2),
    disk_percent numeric(5,2),
    disk_read_mbps numeric(10,2),
    disk_write_mbps numeric(10,2),
    network_sent_mbps numeric(10,2),
    network_recv_mbps numeric(10,2),
    gpu_percent numeric(5,2),
    gpu_memory_used_gb numeric(10,2),
    gpu_temperature numeric(5,2),
    uptime_seconds bigint,
    logged_in_users integer,
    cpu_iowait_percent double precision,
    context_switch_rate double precision,
    swap_in_rate double precision,
    swap_out_rate double precision,
    page_fault_rate double precision,
    major_page_fault_rate double precision,
    CONSTRAINT metrics_cpu_percent_check CHECK (((cpu_percent >= (0)::numeric) AND (cpu_percent <= (100)::numeric))),
    CONSTRAINT metrics_disk_percent_check CHECK (((disk_percent >= (0)::numeric) AND (disk_percent <= (100)::numeric))),
    CONSTRAINT metrics_ram_percent_check CHECK (((ram_percent >= (0)::numeric) AND (ram_percent <= (100)::numeric)))
);


ALTER TABLE public.metrics OWNER TO aayush;

--
-- Name: TABLE metrics; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON TABLE public.metrics IS 'Time-series resource utilization metrics';


--
-- Name: COLUMN metrics.cpu_iowait_percent; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON COLUMN public.metrics.cpu_iowait_percent IS 'CPU time waiting for I/O operations (percentage)';


--
-- Name: COLUMN metrics.context_switch_rate; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON COLUMN public.metrics.context_switch_rate IS 'Context switches per second';


--
-- Name: COLUMN metrics.swap_in_rate; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON COLUMN public.metrics.swap_in_rate IS 'Swap pages in per second';


--
-- Name: COLUMN metrics.swap_out_rate; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON COLUMN public.metrics.swap_out_rate IS 'Swap pages out per second';


--
-- Name: COLUMN metrics.page_fault_rate; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON COLUMN public.metrics.page_fault_rate IS 'Page faults per second';


--
-- Name: COLUMN metrics.major_page_fault_rate; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON COLUMN public.metrics.major_page_fault_rate IS 'Major page faults per second';


--
-- Name: _direct_view_17; Type: VIEW; Schema: _timescaledb_internal; Owner: aayush
--

CREATE VIEW _timescaledb_internal._direct_view_17 AS
 SELECT system_id,
    public.time_bucket('01:00:00'::interval, "timestamp") AS hour_bucket,
    avg(cpu_percent) AS avg_cpu_percent,
    max(cpu_percent) AS max_cpu_percent,
    min(cpu_percent) AS min_cpu_percent,
    percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((cpu_percent)::double precision)) AS p95_cpu_percent,
    stddev(cpu_percent) AS stddev_cpu_percent,
    avg(ram_percent) AS avg_ram_percent,
    max(ram_percent) AS max_ram_percent,
    percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((ram_percent)::double precision)) AS p95_ram_percent,
    stddev(ram_percent) AS stddev_ram_percent,
    avg(gpu_percent) AS avg_gpu_percent,
    max(gpu_percent) AS max_gpu_percent,
    stddev(gpu_percent) AS stddev_gpu_percent,
    avg(disk_percent) AS avg_disk_percent,
    max(disk_percent) AS max_disk_percent,
    stddev(disk_percent) AS stddev_disk_percent,
    count(*) AS metric_count
   FROM public.metrics
  GROUP BY system_id, (public.time_bucket('01:00:00'::interval, "timestamp"));


ALTER VIEW _timescaledb_internal._direct_view_17 OWNER TO aayush;

--
-- Name: _direct_view_18; Type: VIEW; Schema: _timescaledb_internal; Owner: aayush
--

CREATE VIEW _timescaledb_internal._direct_view_18 AS
 SELECT system_id,
    public.time_bucket('1 day'::interval, "timestamp") AS day_bucket,
    avg(cpu_percent) AS avg_cpu_percent,
    max(cpu_percent) AS max_cpu_percent,
    min(cpu_percent) AS min_cpu_percent,
    percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((cpu_percent)::double precision)) AS p95_cpu_percent,
    stddev(cpu_percent) AS stddev_cpu_percent,
    avg(ram_percent) AS avg_ram_percent,
    max(ram_percent) AS max_ram_percent,
    min(ram_percent) AS min_ram_percent,
    percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((ram_percent)::double precision)) AS p95_ram_percent,
    stddev(ram_percent) AS stddev_ram_percent,
    avg(gpu_percent) AS avg_gpu_percent,
    max(gpu_percent) AS max_gpu_percent,
    min(gpu_percent) AS min_gpu_percent,
    stddev(gpu_percent) AS stddev_gpu_percent,
    avg(disk_percent) AS avg_disk_percent,
    max(disk_percent) AS max_disk_percent,
    min(disk_percent) AS min_disk_percent,
    stddev(disk_percent) AS stddev_disk_percent,
    count(*) AS metric_count
   FROM public.metrics
  GROUP BY system_id, (public.time_bucket('1 day'::interval, "timestamp"));


ALTER VIEW _timescaledb_internal._direct_view_18 OWNER TO aayush;

--
-- Name: _hyper_13_1_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._hyper_13_1_chunk (
    CONSTRAINT constraint_1 CHECK ((("timestamp" >= '2025-12-30 05:30:00+05:30'::timestamp with time zone) AND ("timestamp" < '2025-12-31 05:30:00+05:30'::timestamp with time zone)))
)
INHERITS (public.metrics);


ALTER TABLE _timescaledb_internal._hyper_13_1_chunk OWNER TO aayush;

--
-- Name: _hyper_13_2_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._hyper_13_2_chunk (
    CONSTRAINT constraint_2 CHECK ((("timestamp" >= '2025-12-31 05:30:00+05:30'::timestamp with time zone) AND ("timestamp" < '2026-01-01 05:30:00+05:30'::timestamp with time zone)))
)
INHERITS (public.metrics);


ALTER TABLE _timescaledb_internal._hyper_13_2_chunk OWNER TO aayush;

--
-- Name: _hyper_13_3_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._hyper_13_3_chunk (
    CONSTRAINT constraint_3 CHECK ((("timestamp" >= '2026-01-07 05:30:00+05:30'::timestamp with time zone) AND ("timestamp" < '2026-01-08 05:30:00+05:30'::timestamp with time zone)))
)
INHERITS (public.metrics);


ALTER TABLE _timescaledb_internal._hyper_13_3_chunk OWNER TO aayush;

--
-- Name: _hyper_13_4_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._hyper_13_4_chunk (
    CONSTRAINT constraint_4 CHECK ((("timestamp" >= '2026-01-20 05:30:00+05:30'::timestamp with time zone) AND ("timestamp" < '2026-01-21 05:30:00+05:30'::timestamp with time zone)))
)
INHERITS (public.metrics);


ALTER TABLE _timescaledb_internal._hyper_13_4_chunk OWNER TO aayush;

--
-- Name: _materialized_hypertable_17; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._materialized_hypertable_17 (
    system_id integer,
    hour_bucket timestamp with time zone NOT NULL,
    avg_cpu_percent numeric,
    max_cpu_percent numeric,
    min_cpu_percent numeric,
    p95_cpu_percent double precision,
    stddev_cpu_percent numeric,
    avg_ram_percent numeric,
    max_ram_percent numeric,
    p95_ram_percent double precision,
    stddev_ram_percent numeric,
    avg_gpu_percent numeric,
    max_gpu_percent numeric,
    stddev_gpu_percent numeric,
    avg_disk_percent numeric,
    max_disk_percent numeric,
    stddev_disk_percent numeric,
    metric_count bigint
);


ALTER TABLE _timescaledb_internal._materialized_hypertable_17 OWNER TO aayush;

--
-- Name: _hyper_17_14_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._hyper_17_14_chunk (
    CONSTRAINT constraint_11 CHECK (((hour_bucket >= '2025-12-28 05:30:00+05:30'::timestamp with time zone) AND (hour_bucket < '2026-01-07 05:30:00+05:30'::timestamp with time zone)))
)
INHERITS (_timescaledb_internal._materialized_hypertable_17);


ALTER TABLE _timescaledb_internal._hyper_17_14_chunk OWNER TO aayush;

--
-- Name: _hyper_17_15_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._hyper_17_15_chunk (
    CONSTRAINT constraint_12 CHECK (((hour_bucket >= '2026-01-07 05:30:00+05:30'::timestamp with time zone) AND (hour_bucket < '2026-01-17 05:30:00+05:30'::timestamp with time zone)))
)
INHERITS (_timescaledb_internal._materialized_hypertable_17);


ALTER TABLE _timescaledb_internal._hyper_17_15_chunk OWNER TO aayush;

--
-- Name: _hyper_17_16_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._hyper_17_16_chunk (
    CONSTRAINT constraint_13 CHECK (((hour_bucket >= '2026-01-17 05:30:00+05:30'::timestamp with time zone) AND (hour_bucket < '2026-01-27 05:30:00+05:30'::timestamp with time zone)))
)
INHERITS (_timescaledb_internal._materialized_hypertable_17);


ALTER TABLE _timescaledb_internal._hyper_17_16_chunk OWNER TO aayush;

--
-- Name: _materialized_hypertable_18; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._materialized_hypertable_18 (
    system_id integer,
    day_bucket timestamp with time zone NOT NULL,
    avg_cpu_percent numeric,
    max_cpu_percent numeric,
    min_cpu_percent numeric,
    p95_cpu_percent double precision,
    stddev_cpu_percent numeric,
    avg_ram_percent numeric,
    max_ram_percent numeric,
    min_ram_percent numeric,
    p95_ram_percent double precision,
    stddev_ram_percent numeric,
    avg_gpu_percent numeric,
    max_gpu_percent numeric,
    min_gpu_percent numeric,
    stddev_gpu_percent numeric,
    avg_disk_percent numeric,
    max_disk_percent numeric,
    min_disk_percent numeric,
    stddev_disk_percent numeric,
    metric_count bigint
);


ALTER TABLE _timescaledb_internal._materialized_hypertable_18 OWNER TO aayush;

--
-- Name: _hyper_18_17_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._hyper_18_17_chunk (
    CONSTRAINT constraint_14 CHECK (((day_bucket >= '2025-12-28 05:30:00+05:30'::timestamp with time zone) AND (day_bucket < '2026-01-07 05:30:00+05:30'::timestamp with time zone)))
)
INHERITS (_timescaledb_internal._materialized_hypertable_18);


ALTER TABLE _timescaledb_internal._hyper_18_17_chunk OWNER TO aayush;

--
-- Name: _hyper_18_18_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._hyper_18_18_chunk (
    CONSTRAINT constraint_15 CHECK (((day_bucket >= '2026-01-07 05:30:00+05:30'::timestamp with time zone) AND (day_bucket < '2026-01-17 05:30:00+05:30'::timestamp with time zone)))
)
INHERITS (_timescaledb_internal._materialized_hypertable_18);


ALTER TABLE _timescaledb_internal._hyper_18_18_chunk OWNER TO aayush;

--
-- Name: _hyper_18_19_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal._hyper_18_19_chunk (
    CONSTRAINT constraint_16 CHECK (((day_bucket >= '2026-01-17 05:30:00+05:30'::timestamp with time zone) AND (day_bucket < '2026-01-27 05:30:00+05:30'::timestamp with time zone)))
)
INHERITS (_timescaledb_internal._materialized_hypertable_18);


ALTER TABLE _timescaledb_internal._hyper_18_19_chunk OWNER TO aayush;

--
-- Name: _partial_view_17; Type: VIEW; Schema: _timescaledb_internal; Owner: aayush
--

CREATE VIEW _timescaledb_internal._partial_view_17 AS
 SELECT system_id,
    public.time_bucket('01:00:00'::interval, "timestamp") AS hour_bucket,
    avg(cpu_percent) AS avg_cpu_percent,
    max(cpu_percent) AS max_cpu_percent,
    min(cpu_percent) AS min_cpu_percent,
    percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((cpu_percent)::double precision)) AS p95_cpu_percent,
    stddev(cpu_percent) AS stddev_cpu_percent,
    avg(ram_percent) AS avg_ram_percent,
    max(ram_percent) AS max_ram_percent,
    percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((ram_percent)::double precision)) AS p95_ram_percent,
    stddev(ram_percent) AS stddev_ram_percent,
    avg(gpu_percent) AS avg_gpu_percent,
    max(gpu_percent) AS max_gpu_percent,
    stddev(gpu_percent) AS stddev_gpu_percent,
    avg(disk_percent) AS avg_disk_percent,
    max(disk_percent) AS max_disk_percent,
    stddev(disk_percent) AS stddev_disk_percent,
    count(*) AS metric_count
   FROM public.metrics
  GROUP BY system_id, (public.time_bucket('01:00:00'::interval, "timestamp"));


ALTER VIEW _timescaledb_internal._partial_view_17 OWNER TO aayush;

--
-- Name: _partial_view_18; Type: VIEW; Schema: _timescaledb_internal; Owner: aayush
--

CREATE VIEW _timescaledb_internal._partial_view_18 AS
 SELECT system_id,
    public.time_bucket('1 day'::interval, "timestamp") AS day_bucket,
    avg(cpu_percent) AS avg_cpu_percent,
    max(cpu_percent) AS max_cpu_percent,
    min(cpu_percent) AS min_cpu_percent,
    percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((cpu_percent)::double precision)) AS p95_cpu_percent,
    stddev(cpu_percent) AS stddev_cpu_percent,
    avg(ram_percent) AS avg_ram_percent,
    max(ram_percent) AS max_ram_percent,
    min(ram_percent) AS min_ram_percent,
    percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((ram_percent)::double precision)) AS p95_ram_percent,
    stddev(ram_percent) AS stddev_ram_percent,
    avg(gpu_percent) AS avg_gpu_percent,
    max(gpu_percent) AS max_gpu_percent,
    min(gpu_percent) AS min_gpu_percent,
    stddev(gpu_percent) AS stddev_gpu_percent,
    avg(disk_percent) AS avg_disk_percent,
    max(disk_percent) AS max_disk_percent,
    min(disk_percent) AS min_disk_percent,
    stddev(disk_percent) AS stddev_disk_percent,
    count(*) AS metric_count
   FROM public.metrics
  GROUP BY system_id, (public.time_bucket('1 day'::interval, "timestamp"));


ALTER VIEW _timescaledb_internal._partial_view_18 OWNER TO aayush;

--
-- Name: compress_hyper_14_11_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal.compress_hyper_14_11_chunk (
    _ts_meta_count integer,
    system_id integer,
    metric_id _timescaledb_internal.compressed_data,
    _ts_meta_min_1 timestamp with time zone,
    _ts_meta_max_1 timestamp with time zone,
    "timestamp" _timescaledb_internal.compressed_data,
    cpu_percent _timescaledb_internal.compressed_data,
    cpu_temperature _timescaledb_internal.compressed_data,
    ram_percent _timescaledb_internal.compressed_data,
    disk_percent _timescaledb_internal.compressed_data,
    disk_read_mbps _timescaledb_internal.compressed_data,
    disk_write_mbps _timescaledb_internal.compressed_data,
    network_sent_mbps _timescaledb_internal.compressed_data,
    network_recv_mbps _timescaledb_internal.compressed_data,
    gpu_percent _timescaledb_internal.compressed_data,
    gpu_memory_used_gb _timescaledb_internal.compressed_data,
    gpu_temperature _timescaledb_internal.compressed_data,
    uptime_seconds _timescaledb_internal.compressed_data,
    logged_in_users _timescaledb_internal.compressed_data,
    cpu_iowait_percent _timescaledb_internal.compressed_data,
    context_switch_rate _timescaledb_internal.compressed_data,
    swap_in_rate _timescaledb_internal.compressed_data,
    swap_out_rate _timescaledb_internal.compressed_data,
    page_fault_rate _timescaledb_internal.compressed_data,
    major_page_fault_rate _timescaledb_internal.compressed_data
)
WITH (toast_tuple_target='128');
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN _ts_meta_count SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN system_id SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN metric_id SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN _ts_meta_min_1 SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN _ts_meta_max_1 SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN "timestamp" SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN cpu_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN cpu_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN cpu_temperature SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN cpu_temperature SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN ram_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN ram_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN disk_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN disk_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN disk_read_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN disk_read_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN disk_write_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN disk_write_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN network_sent_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN network_sent_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN network_recv_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN network_recv_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN gpu_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN gpu_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN gpu_memory_used_gb SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN gpu_memory_used_gb SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN gpu_temperature SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN gpu_temperature SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN uptime_seconds SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_11_chunk ALTER COLUMN logged_in_users SET STATISTICS 0;


ALTER TABLE _timescaledb_internal.compress_hyper_14_11_chunk OWNER TO aayush;

--
-- Name: compress_hyper_14_12_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal.compress_hyper_14_12_chunk (
    _ts_meta_count integer,
    system_id integer,
    metric_id _timescaledb_internal.compressed_data,
    _ts_meta_min_1 timestamp with time zone,
    _ts_meta_max_1 timestamp with time zone,
    "timestamp" _timescaledb_internal.compressed_data,
    cpu_percent _timescaledb_internal.compressed_data,
    cpu_temperature _timescaledb_internal.compressed_data,
    ram_percent _timescaledb_internal.compressed_data,
    disk_percent _timescaledb_internal.compressed_data,
    disk_read_mbps _timescaledb_internal.compressed_data,
    disk_write_mbps _timescaledb_internal.compressed_data,
    network_sent_mbps _timescaledb_internal.compressed_data,
    network_recv_mbps _timescaledb_internal.compressed_data,
    gpu_percent _timescaledb_internal.compressed_data,
    gpu_memory_used_gb _timescaledb_internal.compressed_data,
    gpu_temperature _timescaledb_internal.compressed_data,
    uptime_seconds _timescaledb_internal.compressed_data,
    logged_in_users _timescaledb_internal.compressed_data,
    cpu_iowait_percent _timescaledb_internal.compressed_data,
    context_switch_rate _timescaledb_internal.compressed_data,
    swap_in_rate _timescaledb_internal.compressed_data,
    swap_out_rate _timescaledb_internal.compressed_data,
    page_fault_rate _timescaledb_internal.compressed_data,
    major_page_fault_rate _timescaledb_internal.compressed_data
)
WITH (toast_tuple_target='128');
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN _ts_meta_count SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN system_id SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN metric_id SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN _ts_meta_min_1 SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN _ts_meta_max_1 SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN "timestamp" SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN cpu_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN cpu_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN cpu_temperature SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN cpu_temperature SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN ram_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN ram_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN disk_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN disk_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN disk_read_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN disk_read_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN disk_write_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN disk_write_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN network_sent_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN network_sent_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN network_recv_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN network_recv_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN gpu_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN gpu_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN gpu_memory_used_gb SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN gpu_memory_used_gb SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN gpu_temperature SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN gpu_temperature SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN uptime_seconds SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_12_chunk ALTER COLUMN logged_in_users SET STATISTICS 0;


ALTER TABLE _timescaledb_internal.compress_hyper_14_12_chunk OWNER TO aayush;

--
-- Name: compress_hyper_14_13_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal.compress_hyper_14_13_chunk (
    _ts_meta_count integer,
    system_id integer,
    metric_id _timescaledb_internal.compressed_data,
    _ts_meta_min_1 timestamp with time zone,
    _ts_meta_max_1 timestamp with time zone,
    "timestamp" _timescaledb_internal.compressed_data,
    cpu_percent _timescaledb_internal.compressed_data,
    cpu_temperature _timescaledb_internal.compressed_data,
    ram_percent _timescaledb_internal.compressed_data,
    disk_percent _timescaledb_internal.compressed_data,
    disk_read_mbps _timescaledb_internal.compressed_data,
    disk_write_mbps _timescaledb_internal.compressed_data,
    network_sent_mbps _timescaledb_internal.compressed_data,
    network_recv_mbps _timescaledb_internal.compressed_data,
    gpu_percent _timescaledb_internal.compressed_data,
    gpu_memory_used_gb _timescaledb_internal.compressed_data,
    gpu_temperature _timescaledb_internal.compressed_data,
    uptime_seconds _timescaledb_internal.compressed_data,
    logged_in_users _timescaledb_internal.compressed_data,
    cpu_iowait_percent _timescaledb_internal.compressed_data,
    context_switch_rate _timescaledb_internal.compressed_data,
    swap_in_rate _timescaledb_internal.compressed_data,
    swap_out_rate _timescaledb_internal.compressed_data,
    page_fault_rate _timescaledb_internal.compressed_data,
    major_page_fault_rate _timescaledb_internal.compressed_data
)
WITH (toast_tuple_target='128');
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN _ts_meta_count SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN system_id SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN metric_id SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN _ts_meta_min_1 SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN _ts_meta_max_1 SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN "timestamp" SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN cpu_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN cpu_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN cpu_temperature SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN cpu_temperature SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN ram_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN ram_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN disk_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN disk_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN disk_read_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN disk_read_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN disk_write_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN disk_write_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN network_sent_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN network_sent_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN network_recv_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN network_recv_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN gpu_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN gpu_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN gpu_memory_used_gb SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN gpu_memory_used_gb SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN gpu_temperature SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN gpu_temperature SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN uptime_seconds SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_13_chunk ALTER COLUMN logged_in_users SET STATISTICS 0;


ALTER TABLE _timescaledb_internal.compress_hyper_14_13_chunk OWNER TO aayush;

--
-- Name: compress_hyper_14_20_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TABLE _timescaledb_internal.compress_hyper_14_20_chunk (
    _ts_meta_count integer,
    system_id integer,
    metric_id _timescaledb_internal.compressed_data,
    _ts_meta_min_1 timestamp with time zone,
    _ts_meta_max_1 timestamp with time zone,
    "timestamp" _timescaledb_internal.compressed_data,
    cpu_percent _timescaledb_internal.compressed_data,
    cpu_temperature _timescaledb_internal.compressed_data,
    ram_percent _timescaledb_internal.compressed_data,
    disk_percent _timescaledb_internal.compressed_data,
    disk_read_mbps _timescaledb_internal.compressed_data,
    disk_write_mbps _timescaledb_internal.compressed_data,
    network_sent_mbps _timescaledb_internal.compressed_data,
    network_recv_mbps _timescaledb_internal.compressed_data,
    gpu_percent _timescaledb_internal.compressed_data,
    gpu_memory_used_gb _timescaledb_internal.compressed_data,
    gpu_temperature _timescaledb_internal.compressed_data,
    uptime_seconds _timescaledb_internal.compressed_data,
    logged_in_users _timescaledb_internal.compressed_data,
    cpu_iowait_percent _timescaledb_internal.compressed_data,
    context_switch_rate _timescaledb_internal.compressed_data,
    swap_in_rate _timescaledb_internal.compressed_data,
    swap_out_rate _timescaledb_internal.compressed_data,
    page_fault_rate _timescaledb_internal.compressed_data,
    major_page_fault_rate _timescaledb_internal.compressed_data
)
WITH (toast_tuple_target='128');
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN _ts_meta_count SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN system_id SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN metric_id SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN _ts_meta_min_1 SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN _ts_meta_max_1 SET STATISTICS 1000;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN "timestamp" SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN cpu_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN cpu_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN cpu_temperature SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN cpu_temperature SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN ram_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN ram_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN disk_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN disk_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN disk_read_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN disk_read_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN disk_write_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN disk_write_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN network_sent_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN network_sent_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN network_recv_mbps SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN network_recv_mbps SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN gpu_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN gpu_percent SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN gpu_memory_used_gb SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN gpu_memory_used_gb SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN gpu_temperature SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN gpu_temperature SET STORAGE EXTENDED;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN uptime_seconds SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN logged_in_users SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN cpu_iowait_percent SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN context_switch_rate SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN swap_in_rate SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN swap_out_rate SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN page_fault_rate SET STATISTICS 0;
ALTER TABLE ONLY _timescaledb_internal.compress_hyper_14_20_chunk ALTER COLUMN major_page_fault_rate SET STATISTICS 0;


ALTER TABLE _timescaledb_internal.compress_hyper_14_20_chunk OWNER TO aayush;

--
-- Name: collection_credentials; Type: TABLE; Schema: public; Owner: aayush
--

CREATE TABLE public.collection_credentials (
    credential_id integer NOT NULL,
    credential_name character varying(100) NOT NULL,
    credential_type character varying(50) NOT NULL,
    username character varying(255),
    password_encrypted bytea,
    ssh_key_path text,
    snmp_community character varying(100),
    additional_config jsonb,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    last_used timestamp with time zone,
    used_count integer DEFAULT 0
);


ALTER TABLE public.collection_credentials OWNER TO aayush;

--
-- Name: TABLE collection_credentials; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON TABLE public.collection_credentials IS 'Encrypted credentials for remote system access';


--
-- Name: collection_credentials_credential_id_seq; Type: SEQUENCE; Schema: public; Owner: aayush
--

CREATE SEQUENCE public.collection_credentials_credential_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.collection_credentials_credential_id_seq OWNER TO aayush;

--
-- Name: collection_credentials_credential_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aayush
--

ALTER SEQUENCE public.collection_credentials_credential_id_seq OWNED BY public.collection_credentials.credential_id;


--
-- Name: daily_performance_stats; Type: VIEW; Schema: public; Owner: aayush
--

CREATE VIEW public.daily_performance_stats AS
 SELECT system_id,
    day_bucket,
    avg_cpu_percent,
    max_cpu_percent,
    min_cpu_percent,
    p95_cpu_percent,
    stddev_cpu_percent,
    avg_ram_percent,
    max_ram_percent,
    min_ram_percent,
    p95_ram_percent,
    stddev_ram_percent,
    avg_gpu_percent,
    max_gpu_percent,
    min_gpu_percent,
    stddev_gpu_percent,
    avg_disk_percent,
    max_disk_percent,
    min_disk_percent,
    stddev_disk_percent,
    metric_count
   FROM _timescaledb_internal._materialized_hypertable_18;


ALTER VIEW public.daily_performance_stats OWNER TO aayush;

--
-- Name: departments; Type: TABLE; Schema: public; Owner: aayush
--

CREATE TABLE public.departments (
    dept_id integer NOT NULL,
    dept_name character varying(100) NOT NULL,
    dept_code character varying(20),
    vlan_id character varying(20),
    subnet_cidr cidr,
    description text,
    hod_id integer
);


ALTER TABLE public.departments OWNER TO aayush;

--
-- Name: TABLE departments; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON TABLE public.departments IS 'Academic departments and their network configuration';


--
-- Name: departments_dept_id_seq; Type: SEQUENCE; Schema: public; Owner: aayush
--

CREATE SEQUENCE public.departments_dept_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.departments_dept_id_seq OWNER TO aayush;

--
-- Name: departments_dept_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aayush
--

ALTER SEQUENCE public.departments_dept_id_seq OWNED BY public.departments.dept_id;


--
-- Name: hods; Type: TABLE; Schema: public; Owner: aayush
--

CREATE TABLE public.hods (
    hod_id integer NOT NULL,
    hod_name character varying(200) NOT NULL,
    hod_email character varying(220)
);


ALTER TABLE public.hods OWNER TO aayush;

--
-- Name: TABLE hods; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON TABLE public.hods IS 'HODs information of RVCE';


--
-- Name: hods_hod_id_seq; Type: SEQUENCE; Schema: public; Owner: aayush
--

CREATE SEQUENCE public.hods_hod_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.hods_hod_id_seq OWNER TO aayush;

--
-- Name: hods_hod_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aayush
--

ALTER SEQUENCE public.hods_hod_id_seq OWNED BY public.hods.hod_id;


--
-- Name: hourly_performance_stats; Type: VIEW; Schema: public; Owner: aayush
--

CREATE VIEW public.hourly_performance_stats AS
 SELECT system_id,
    hour_bucket,
    avg_cpu_percent,
    max_cpu_percent,
    min_cpu_percent,
    p95_cpu_percent,
    stddev_cpu_percent,
    avg_ram_percent,
    max_ram_percent,
    p95_ram_percent,
    stddev_ram_percent,
    avg_gpu_percent,
    max_gpu_percent,
    stddev_gpu_percent,
    avg_disk_percent,
    max_disk_percent,
    stddev_disk_percent,
    metric_count
   FROM _timescaledb_internal._materialized_hypertable_17;


ALTER VIEW public.hourly_performance_stats OWNER TO aayush;

--
-- Name: lab_assistants; Type: TABLE; Schema: public; Owner: aayush
--

CREATE TABLE public.lab_assistants (
    lab_assistant_id integer NOT NULL,
    lab_assistant_name character varying(200) NOT NULL,
    lab_assistant_email character varying(250),
    lab_assistant_dept integer,
    lab_assigned integer
);


ALTER TABLE public.lab_assistants OWNER TO aayush;

--
-- Name: TABLE lab_assistants; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON TABLE public.lab_assistants IS 'Lab Assistants of RVCE';


--
-- Name: lab_assistants_lab_assistant_id_seq; Type: SEQUENCE; Schema: public; Owner: aayush
--

CREATE SEQUENCE public.lab_assistants_lab_assistant_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.lab_assistants_lab_assistant_id_seq OWNER TO aayush;

--
-- Name: lab_assistants_lab_assistant_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aayush
--

ALTER SEQUENCE public.lab_assistants_lab_assistant_id_seq OWNED BY public.lab_assistants.lab_assistant_id;


--
-- Name: labs; Type: TABLE; Schema: public; Owner: aayush
--

CREATE TABLE public.labs (
    lab_id integer NOT NULL,
    lab_dept integer,
    lab_number integer,
    assistant_ids integer[]
);


ALTER TABLE public.labs OWNER TO aayush;

--
-- Name: TABLE labs; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON TABLE public.labs IS 'Labs of RVCE';


--
-- Name: labs_lab_id_seq; Type: SEQUENCE; Schema: public; Owner: aayush
--

CREATE SEQUENCE public.labs_lab_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.labs_lab_id_seq OWNER TO aayush;

--
-- Name: labs_lab_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aayush
--

ALTER SEQUENCE public.labs_lab_id_seq OWNED BY public.labs.lab_id;


--
-- Name: maintainence_logs; Type: TABLE; Schema: public; Owner: aayush
--

CREATE TABLE public.maintainence_logs (
    maintainence_id bigint NOT NULL,
    system_id integer,
    date_at timestamp with time zone DEFAULT now() NOT NULL,
    is_acknowledged boolean DEFAULT false,
    acknowledged_at timestamp with time zone,
    acknowledged_by character varying(100),
    resolved_at timestamp with time zone,
    severity character varying(20) NOT NULL,
    message text NOT NULL
);


ALTER TABLE public.maintainence_logs OWNER TO aayush;

--
-- Name: maintainence_logs_maintainence_id_seq; Type: SEQUENCE; Schema: public; Owner: aayush
--

CREATE SEQUENCE public.maintainence_logs_maintainence_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.maintainence_logs_maintainence_id_seq OWNER TO aayush;

--
-- Name: maintainence_logs_maintainence_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aayush
--

ALTER SEQUENCE public.maintainence_logs_maintainence_id_seq OWNED BY public.maintainence_logs.maintainence_id;


--
-- Name: metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: aayush
--

CREATE SEQUENCE public.metrics_metric_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.metrics_metric_id_seq OWNER TO aayush;

--
-- Name: metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aayush
--

ALTER SEQUENCE public.metrics_metric_id_seq OWNED BY public.metrics.metric_id;


--
-- Name: network_scans; Type: TABLE; Schema: public; Owner: aayush
--

CREATE TABLE public.network_scans (
    scan_id integer NOT NULL,
    dept_id integer,
    scan_type character varying(50) NOT NULL,
    target_range character varying(100) NOT NULL,
    scan_start timestamp with time zone NOT NULL,
    scan_end timestamp with time zone,
    duration_seconds integer GENERATED ALWAYS AS ((EXTRACT(epoch FROM (scan_end - scan_start)))::integer) STORED,
    systems_found integer DEFAULT 0,
    status character varying(20) DEFAULT 'running'::character varying,
    error_message text,
    scan_parameters jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.network_scans OWNER TO aayush;

--
-- Name: TABLE network_scans; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON TABLE public.network_scans IS 'History of network discovery scans';


--
-- Name: network_scans_scan_id_seq; Type: SEQUENCE; Schema: public; Owner: aayush
--

CREATE SEQUENCE public.network_scans_scan_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.network_scans_scan_id_seq OWNER TO aayush;

--
-- Name: network_scans_scan_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aayush
--

ALTER SEQUENCE public.network_scans_scan_id_seq OWNED BY public.network_scans.scan_id;


--
-- Name: performance_summaries; Type: TABLE; Schema: public; Owner: aayush
--

CREATE TABLE public.performance_summaries (
    summary_id bigint NOT NULL,
    system_id integer NOT NULL,
    period_type character varying(20) NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    avg_cpu_percent numeric(5,2),
    max_cpu_percent numeric(5,2),
    min_cpu_percent numeric(5,2),
    avg_ram_percent numeric(5,2),
    max_ram_percent numeric(5,2),
    avg_gpu_percent numeric(5,2),
    max_gpu_percent numeric(5,2),
    uptime_minutes integer,
    anomaly_count integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    stddev_cpu_percent numeric(5,2),
    stddev_ram_percent numeric(5,2),
    stddev_gpu_percent numeric(5,2),
    stddev_disk_percent numeric(5,2),
    min_ram_percent numeric(5,2),
    min_gpu_percent numeric(5,2),
    min_disk_percent numeric(5,2),
    metric_count integer
);


ALTER TABLE public.performance_summaries OWNER TO aayush;

--
-- Name: TABLE performance_summaries; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON TABLE public.performance_summaries IS 'Aggregated performance statistics by time period. Includes variance metrics for CFRS computation. No hardcoded thresholds.';


--
-- Name: performance_summaries_summary_id_seq; Type: SEQUENCE; Schema: public; Owner: aayush
--

CREATE SEQUENCE public.performance_summaries_summary_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.performance_summaries_summary_id_seq OWNER TO aayush;

--
-- Name: performance_summaries_summary_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aayush
--

ALTER SEQUENCE public.performance_summaries_summary_id_seq OWNED BY public.performance_summaries.summary_id;


--
-- Name: system_baselines; Type: TABLE; Schema: public; Owner: aayush
--

CREATE TABLE public.system_baselines (
    baseline_id integer NOT NULL,
    system_id integer NOT NULL,
    metric_name character varying(50) NOT NULL,
    baseline_mean numeric(10,4) NOT NULL,
    baseline_stddev numeric(10,4) NOT NULL,
    baseline_median numeric(10,4),
    baseline_p95 numeric(10,4),
    baseline_start timestamp with time zone NOT NULL,
    baseline_end timestamp with time zone NOT NULL,
    sample_count integer NOT NULL,
    computed_at timestamp with time zone DEFAULT now(),
    is_active boolean DEFAULT true
);


ALTER TABLE public.system_baselines OWNER TO aayush;

--
-- Name: TABLE system_baselines; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON TABLE public.system_baselines IS 'Statistical baselines for CFRS deviation component. Stores mean/stddev for z-score computation. Does NOT compute CFRS internally.';


--
-- Name: system_baselines_baseline_id_seq; Type: SEQUENCE; Schema: public; Owner: aayush
--

CREATE SEQUENCE public.system_baselines_baseline_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.system_baselines_baseline_id_seq OWNER TO aayush;

--
-- Name: system_baselines_baseline_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aayush
--

ALTER SEQUENCE public.system_baselines_baseline_id_seq OWNED BY public.system_baselines.baseline_id;


--
-- Name: systems; Type: TABLE; Schema: public; Owner: aayush
--

CREATE TABLE public.systems (
    system_id integer NOT NULL,
    system_number integer,
    lab_id integer,
    dept_id integer,
    hostname character varying(255) NOT NULL,
    ip_address inet NOT NULL,
    mac_address macaddr,
    cpu_model character varying(255),
    cpu_cores integer,
    ram_total_gb numeric(10,2),
    disk_total_gb numeric(10,2),
    gpu_model character varying(255),
    gpu_memory numeric(10,2),
    snmp_enabled boolean DEFAULT false,
    ssh_port integer DEFAULT 22,
    status character varying(20) DEFAULT 'discovered'::character varying,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.systems OWNER TO aayush;

--
-- Name: TABLE systems; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON TABLE public.systems IS 'Discovered and monitored computer systems';


--
-- Name: systems_system_id_seq; Type: SEQUENCE; Schema: public; Owner: aayush
--

CREATE SEQUENCE public.systems_system_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.systems_system_id_seq OWNER TO aayush;

--
-- Name: systems_system_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: aayush
--

ALTER SEQUENCE public.systems_system_id_seq OWNED BY public.systems.system_id;


--
-- Name: v_daily_resource_trends; Type: VIEW; Schema: public; Owner: aayush
--

CREATE VIEW public.v_daily_resource_trends AS
 SELECT system_id,
    (day_bucket)::date AS date,
    day_bucket,
    avg_cpu_percent,
    stddev_cpu_percent,
    max_cpu_percent,
    avg_ram_percent,
    stddev_ram_percent,
    max_ram_percent,
    avg_gpu_percent,
    stddev_gpu_percent,
    max_gpu_percent,
    avg_disk_percent,
    stddev_disk_percent,
    max_disk_percent,
    metric_count
   FROM public.daily_performance_stats
  ORDER BY system_id, day_bucket;


ALTER VIEW public.v_daily_resource_trends OWNER TO aayush;

--
-- Name: VIEW v_daily_resource_trends; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON VIEW public.v_daily_resource_trends IS 'Daily resource utilization for trend analysis. Suitable for linear regression to compute degradation slopes. Part of CFRS trend component input.';


--
-- Name: v_department_stats; Type: VIEW; Schema: public; Owner: aayush
--

CREATE VIEW public.v_department_stats AS
 SELECT d.dept_name,
    count(s.system_id) AS total_systems,
    count(s.system_id) FILTER (WHERE ((s.status)::text = 'active'::text)) AS active_systems,
    count(s.system_id) FILTER (WHERE ((s.status)::text = 'offline'::text)) AS offline_systems
   FROM (public.departments d
     LEFT JOIN public.systems s USING (dept_id))
  GROUP BY d.dept_id, d.dept_name;


ALTER VIEW public.v_department_stats OWNER TO aayush;

--
-- Name: v_latest_metrics; Type: VIEW; Schema: public; Owner: aayush
--

CREATE VIEW public.v_latest_metrics AS
 SELECT DISTINCT ON (system_id) system_id,
    "timestamp",
    cpu_percent,
    ram_percent,
    disk_percent,
    logged_in_users
   FROM public.metrics
  ORDER BY system_id, "timestamp" DESC;


ALTER VIEW public.v_latest_metrics OWNER TO aayush;

--
-- Name: v_systems_overview; Type: VIEW; Schema: public; Owner: aayush
--

CREATE VIEW public.v_systems_overview AS
 SELECT s.system_id,
    s.hostname,
    (s.ip_address)::text AS ip_address,
    (s.mac_address)::text AS mac_address,
    d.dept_name,
    d.dept_code,
    s.status
   FROM (public.systems s
     LEFT JOIN public.departments d USING (dept_id));


ALTER VIEW public.v_systems_overview OWNER TO aayush;

--
-- Name: v_systems_with_status; Type: VIEW; Schema: public; Owner: aayush
--

CREATE VIEW public.v_systems_with_status AS
 SELECT s.system_id,
    s.system_number,
    s.lab_id,
    s.dept_id,
    s.hostname,
    s.ip_address,
    s.mac_address,
    s.cpu_model,
    s.cpu_cores,
    s.ram_total_gb,
    s.disk_total_gb,
    s.gpu_model,
    s.gpu_memory,
    s.snmp_enabled,
    s.ssh_port,
    s.status,
    s.notes,
    s.created_at,
    s.updated_at,
    m.last_metric_time,
        CASE
            WHEN (m.last_metric_time IS NULL) THEN 'unknown'::text
            WHEN (m.last_metric_time < (now() - '00:10:00'::interval)) THEN 'offline'::text
            ELSE 'active'::text
        END AS computed_status
   FROM (public.systems s
     LEFT JOIN ( SELECT metrics.system_id,
            max(metrics."timestamp") AS last_metric_time
           FROM public.metrics
          GROUP BY metrics.system_id) m ON ((s.system_id = m.system_id)));


ALTER VIEW public.v_systems_with_status OWNER TO aayush;

--
-- Name: VIEW v_systems_with_status; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON VIEW public.v_systems_with_status IS 'Systems with dynamically computed status based on last metrics timestamp. A system is considered offline if no metrics received in last 10 minutes.';


--
-- Name: v_weekly_resource_trends; Type: VIEW; Schema: public; Owner: aayush
--

CREATE VIEW public.v_weekly_resource_trends AS
 SELECT system_id,
    public.time_bucket('7 days'::interval, day_bucket) AS week_bucket,
    avg(avg_cpu_percent) AS avg_cpu_weekly,
    stddev(avg_cpu_percent) AS stddev_cpu_weekly,
    max(max_cpu_percent) AS peak_cpu_weekly,
    avg(avg_ram_percent) AS avg_ram_weekly,
    stddev(avg_ram_percent) AS stddev_ram_weekly,
    max(max_ram_percent) AS peak_ram_weekly,
    avg(avg_gpu_percent) AS avg_gpu_weekly,
    stddev(avg_gpu_percent) AS stddev_gpu_weekly,
    max(max_gpu_percent) AS peak_gpu_weekly,
    avg(avg_disk_percent) AS avg_disk_weekly,
    stddev(avg_disk_percent) AS stddev_disk_weekly,
    max(max_disk_percent) AS peak_disk_weekly,
    sum(metric_count) AS total_samples
   FROM public.daily_performance_stats
  GROUP BY system_id, (public.time_bucket('7 days'::interval, day_bucket))
  ORDER BY system_id, (public.time_bucket('7 days'::interval, day_bucket));


ALTER VIEW public.v_weekly_resource_trends OWNER TO aayush;

--
-- Name: VIEW v_weekly_resource_trends; Type: COMMENT; Schema: public; Owner: aayush
--

COMMENT ON VIEW public.v_weekly_resource_trends IS 'Weekly aggregated trends for multi-day pattern analysis. Supports CFRS trend component with longer time windows.';


--
-- Name: _hyper_13_1_chunk metric_id; Type: DEFAULT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_1_chunk ALTER COLUMN metric_id SET DEFAULT nextval('public.metrics_metric_id_seq'::regclass);


--
-- Name: _hyper_13_1_chunk timestamp; Type: DEFAULT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_1_chunk ALTER COLUMN "timestamp" SET DEFAULT now();


--
-- Name: _hyper_13_2_chunk metric_id; Type: DEFAULT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_2_chunk ALTER COLUMN metric_id SET DEFAULT nextval('public.metrics_metric_id_seq'::regclass);


--
-- Name: _hyper_13_2_chunk timestamp; Type: DEFAULT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_2_chunk ALTER COLUMN "timestamp" SET DEFAULT now();


--
-- Name: _hyper_13_3_chunk metric_id; Type: DEFAULT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_3_chunk ALTER COLUMN metric_id SET DEFAULT nextval('public.metrics_metric_id_seq'::regclass);


--
-- Name: _hyper_13_3_chunk timestamp; Type: DEFAULT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_3_chunk ALTER COLUMN "timestamp" SET DEFAULT now();


--
-- Name: _hyper_13_4_chunk metric_id; Type: DEFAULT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_4_chunk ALTER COLUMN metric_id SET DEFAULT nextval('public.metrics_metric_id_seq'::regclass);


--
-- Name: _hyper_13_4_chunk timestamp; Type: DEFAULT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_4_chunk ALTER COLUMN "timestamp" SET DEFAULT now();


--
-- Name: collection_credentials credential_id; Type: DEFAULT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.collection_credentials ALTER COLUMN credential_id SET DEFAULT nextval('public.collection_credentials_credential_id_seq'::regclass);


--
-- Name: departments dept_id; Type: DEFAULT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.departments ALTER COLUMN dept_id SET DEFAULT nextval('public.departments_dept_id_seq'::regclass);


--
-- Name: hods hod_id; Type: DEFAULT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.hods ALTER COLUMN hod_id SET DEFAULT nextval('public.hods_hod_id_seq'::regclass);


--
-- Name: lab_assistants lab_assistant_id; Type: DEFAULT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.lab_assistants ALTER COLUMN lab_assistant_id SET DEFAULT nextval('public.lab_assistants_lab_assistant_id_seq'::regclass);


--
-- Name: labs lab_id; Type: DEFAULT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.labs ALTER COLUMN lab_id SET DEFAULT nextval('public.labs_lab_id_seq'::regclass);


--
-- Name: maintainence_logs maintainence_id; Type: DEFAULT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.maintainence_logs ALTER COLUMN maintainence_id SET DEFAULT nextval('public.maintainence_logs_maintainence_id_seq'::regclass);


--
-- Name: metrics metric_id; Type: DEFAULT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.metrics_metric_id_seq'::regclass);


--
-- Name: network_scans scan_id; Type: DEFAULT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.network_scans ALTER COLUMN scan_id SET DEFAULT nextval('public.network_scans_scan_id_seq'::regclass);


--
-- Name: performance_summaries summary_id; Type: DEFAULT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.performance_summaries ALTER COLUMN summary_id SET DEFAULT nextval('public.performance_summaries_summary_id_seq'::regclass);


--
-- Name: system_baselines baseline_id; Type: DEFAULT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.system_baselines ALTER COLUMN baseline_id SET DEFAULT nextval('public.system_baselines_baseline_id_seq'::regclass);


--
-- Name: systems system_id; Type: DEFAULT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.systems ALTER COLUMN system_id SET DEFAULT nextval('public.systems_system_id_seq'::regclass);


--
-- Data for Name: hypertable; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.hypertable (id, schema_name, table_name, associated_schema_name, associated_table_prefix, num_dimensions, chunk_sizing_func_schema, chunk_sizing_func_name, chunk_target_size, compression_state, compressed_hypertable_id, status) FROM stdin;
13	public	metrics	_timescaledb_internal	_hyper_13	1	_timescaledb_functions	calculate_chunk_interval	0	1	14	0
14	_timescaledb_internal	_compressed_hypertable_14	_timescaledb_internal	_hyper_14	0	_timescaledb_functions	calculate_chunk_interval	0	2	\N	0
17	_timescaledb_internal	_materialized_hypertable_17	_timescaledb_internal	_hyper_17	1	_timescaledb_functions	calculate_chunk_interval	0	0	\N	0
18	_timescaledb_internal	_materialized_hypertable_18	_timescaledb_internal	_hyper_18	1	_timescaledb_functions	calculate_chunk_interval	0	0	\N	0
\.


--
-- Data for Name: chunk; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.chunk (id, hypertable_id, schema_name, table_name, compressed_chunk_id, dropped, status, osm_chunk, creation_time) FROM stdin;
11	14	_timescaledb_internal	compress_hyper_14_11_chunk	\N	f	0	f	2026-01-20 14:19:18.600488+05:30
1	13	_timescaledb_internal	_hyper_13_1_chunk	11	f	1	f	2026-01-20 14:19:17.995311+05:30
12	14	_timescaledb_internal	compress_hyper_14_12_chunk	\N	f	0	f	2026-01-20 14:19:18.647587+05:30
2	13	_timescaledb_internal	_hyper_13_2_chunk	12	f	1	f	2026-01-20 14:19:18.035328+05:30
13	14	_timescaledb_internal	compress_hyper_14_13_chunk	\N	f	0	f	2026-01-20 14:19:18.676668+05:30
3	13	_timescaledb_internal	_hyper_13_3_chunk	13	f	1	f	2026-01-20 14:19:18.055894+05:30
14	17	_timescaledb_internal	_hyper_17_14_chunk	\N	f	0	f	2026-01-25 00:39:06.344207+05:30
15	17	_timescaledb_internal	_hyper_17_15_chunk	\N	f	0	f	2026-01-25 00:39:06.358287+05:30
16	17	_timescaledb_internal	_hyper_17_16_chunk	\N	f	0	f	2026-01-25 00:39:06.372748+05:30
17	18	_timescaledb_internal	_hyper_18_17_chunk	\N	f	0	f	2026-01-25 00:39:06.431774+05:30
18	18	_timescaledb_internal	_hyper_18_18_chunk	\N	f	0	f	2026-01-25 00:39:06.444517+05:30
19	18	_timescaledb_internal	_hyper_18_19_chunk	\N	f	0	f	2026-01-25 00:39:06.460387+05:30
20	14	_timescaledb_internal	compress_hyper_14_20_chunk	\N	f	0	f	2026-01-28 18:33:55.137409+05:30
4	13	_timescaledb_internal	_hyper_13_4_chunk	20	f	1	f	2026-01-20 14:19:18.078381+05:30
\.


--
-- Data for Name: chunk_column_stats; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.chunk_column_stats (id, hypertable_id, chunk_id, column_name, range_start, range_end, valid) FROM stdin;
\.


--
-- Data for Name: dimension; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.dimension (id, hypertable_id, column_name, column_type, aligned, num_slices, partitioning_func_schema, partitioning_func, interval_length, compress_interval_length, integer_now_func_schema, integer_now_func) FROM stdin;
10	13	timestamp	timestamp with time zone	t	\N	\N	\N	86400000000	\N	\N	\N
13	17	hour_bucket	timestamp with time zone	t	\N	\N	\N	864000000000	\N	\N	\N
14	18	day_bucket	timestamp with time zone	t	\N	\N	\N	864000000000	\N	\N	\N
\.


--
-- Data for Name: dimension_slice; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.dimension_slice (id, dimension_id, range_start, range_end) FROM stdin;
1	10	1767052800000000	1767139200000000
2	10	1767139200000000	1767225600000000
3	10	1767744000000000	1767830400000000
4	10	1768867200000000	1768953600000000
11	13	1766880000000000	1767744000000000
12	13	1767744000000000	1768608000000000
13	13	1768608000000000	1769472000000000
14	14	1766880000000000	1767744000000000
15	14	1767744000000000	1768608000000000
16	14	1768608000000000	1769472000000000
\.


--
-- Data for Name: chunk_constraint; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.chunk_constraint (chunk_id, dimension_slice_id, constraint_name, hypertable_constraint_name) FROM stdin;
1	1	constraint_1	\N
1	\N	1_1_metrics_pkey	metrics_pkey
1	\N	1_2_metrics_system_id_fkey	metrics_system_id_fkey
1	\N	1_3_unique_system_timestamp	unique_system_timestamp
2	2	constraint_2	\N
2	\N	2_4_metrics_pkey	metrics_pkey
2	\N	2_5_metrics_system_id_fkey	metrics_system_id_fkey
2	\N	2_6_unique_system_timestamp	unique_system_timestamp
3	3	constraint_3	\N
3	\N	3_7_metrics_pkey	metrics_pkey
3	\N	3_8_metrics_system_id_fkey	metrics_system_id_fkey
3	\N	3_9_unique_system_timestamp	unique_system_timestamp
4	4	constraint_4	\N
4	\N	4_10_metrics_pkey	metrics_pkey
4	\N	4_11_metrics_system_id_fkey	metrics_system_id_fkey
4	\N	4_12_unique_system_timestamp	unique_system_timestamp
14	11	constraint_11	\N
15	12	constraint_12	\N
16	13	constraint_13	\N
17	14	constraint_14	\N
18	15	constraint_15	\N
19	16	constraint_16	\N
\.


--
-- Data for Name: compression_chunk_size; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.compression_chunk_size (chunk_id, compressed_chunk_id, uncompressed_heap_size, uncompressed_toast_size, uncompressed_index_size, compressed_heap_size, compressed_toast_size, compressed_index_size, numrows_pre_compression, numrows_post_compression, numrows_frozen_immediately) FROM stdin;
1	11	8192	0	65536	16384	8192	16384	13	1	1
2	12	65536	0	114688	16384	32768	16384	319	1	1
3	13	49152	0	65536	16384	32768	16384	188	1	1
4	20	253952	0	360448	16384	81920	16384	1756	2	2
\.


--
-- Data for Name: compression_settings; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.compression_settings (relid, compress_relid, segmentby, orderby, orderby_desc, orderby_nullsfirst, index) FROM stdin;
_timescaledb_internal._hyper_13_1_chunk	_timescaledb_internal.compress_hyper_14_11_chunk	{system_id}	{timestamp}	{t}	{t}	[{"type": "minmax", "column": "timestamp", "source": "orderby"}]
_timescaledb_internal._hyper_13_2_chunk	_timescaledb_internal.compress_hyper_14_12_chunk	{system_id}	{timestamp}	{t}	{t}	[{"type": "minmax", "column": "timestamp", "source": "orderby"}]
_timescaledb_internal._hyper_13_3_chunk	_timescaledb_internal.compress_hyper_14_13_chunk	{system_id}	{timestamp}	{t}	{t}	[{"type": "minmax", "column": "timestamp", "source": "orderby"}]
public.metrics	\N	{system_id}	{timestamp}	{t}	{t}	\N
_timescaledb_internal._hyper_13_4_chunk	_timescaledb_internal.compress_hyper_14_20_chunk	{system_id}	{timestamp}	{t}	{t}	[{"type": "minmax", "column": "timestamp", "source": "orderby"}]
\.


--
-- Data for Name: continuous_agg; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.continuous_agg (mat_hypertable_id, raw_hypertable_id, parent_mat_hypertable_id, user_view_schema, user_view_name, partial_view_schema, partial_view_name, direct_view_schema, direct_view_name, materialized_only, finalized) FROM stdin;
17	13	\N	public	hourly_performance_stats	_timescaledb_internal	_partial_view_17	_timescaledb_internal	_direct_view_17	t	t
18	13	\N	public	daily_performance_stats	_timescaledb_internal	_partial_view_18	_timescaledb_internal	_direct_view_18	t	t
\.


--
-- Data for Name: continuous_agg_migrate_plan; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.continuous_agg_migrate_plan (mat_hypertable_id, start_ts, end_ts, user_view_definition) FROM stdin;
\.


--
-- Data for Name: continuous_agg_migrate_plan_step; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.continuous_agg_migrate_plan_step (mat_hypertable_id, step_id, status, start_ts, end_ts, type, config) FROM stdin;
\.


--
-- Data for Name: continuous_aggs_bucket_function; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.continuous_aggs_bucket_function (mat_hypertable_id, bucket_func, bucket_width, bucket_origin, bucket_offset, bucket_timezone, bucket_fixed_width) FROM stdin;
17	public.time_bucket(interval,timestamp with time zone)	01:00:00	\N	\N	\N	t
18	public.time_bucket(interval,timestamp with time zone)	1 day	\N	\N	\N	t
\.


--
-- Data for Name: continuous_aggs_hypertable_invalidation_log; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log (hypertable_id, lowest_modified_value, greatest_modified_value) FROM stdin;
\.


--
-- Data for Name: continuous_aggs_invalidation_threshold; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.continuous_aggs_invalidation_threshold (hypertable_id, watermark) FROM stdin;
13	1768953600000000
\.


--
-- Data for Name: continuous_aggs_materialization_invalidation_log; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.continuous_aggs_materialization_invalidation_log (materialization_id, lowest_modified_value, greatest_modified_value) FROM stdin;
17	-9223372036854775808	-210866803200000001
17	1768903200000000	9223372036854775807
18	-9223372036854775808	-210866803200000001
18	1768953600000000	9223372036854775807
\.


--
-- Data for Name: continuous_aggs_materialization_ranges; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.continuous_aggs_materialization_ranges (materialization_id, lowest_modified_value, greatest_modified_value) FROM stdin;
\.


--
-- Data for Name: continuous_aggs_watermark; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.continuous_aggs_watermark (mat_hypertable_id, watermark) FROM stdin;
17	1768903200000000
18	1768953600000000
\.


--
-- Data for Name: metadata; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.metadata (key, value, include_in_telemetry) FROM stdin;
install_timestamp	2025-11-25 10:45:46.820902+05:30	t
timescaledb_version	2.23.1	f
exported_uuid	b34bfa66-e26d-43e7-a0ed-f979b8119be3	t
\.


--
-- Data for Name: tablespace; Type: TABLE DATA; Schema: _timescaledb_catalog; Owner: postgres
--

COPY _timescaledb_catalog.tablespace (id, hypertable_id, tablespace_name) FROM stdin;
\.


--
-- Data for Name: bgw_job; Type: TABLE DATA; Schema: _timescaledb_config; Owner: postgres
--

COPY _timescaledb_config.bgw_job (id, application_name, schedule_interval, max_runtime, max_retries, retry_period, proc_schema, proc_name, owner, scheduled, fixed_schedule, initial_start, hypertable_id, config, check_schema, check_name, timezone) FROM stdin;
1006	Columnstore Policy [1006]	12:00:00	00:00:00	-1	01:00:00	_timescaledb_functions	policy_compression	aayush	t	f	\N	13	{"hypertable_id": 13, "compress_after": "7 days"}	_timescaledb_functions	policy_compression_check	\N
1007	Retention Policy [1007]	1 day	00:05:00	-1	00:05:00	_timescaledb_functions	policy_retention	aayush	t	f	\N	13	{"drop_after": "1 year", "hypertable_id": 13}	_timescaledb_functions	policy_retention_check	\N
\.


--
-- Data for Name: _compressed_hypertable_14; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._compressed_hypertable_14  FROM stdin;
\.


--
-- Data for Name: _hyper_13_1_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._hyper_13_1_chunk (metric_id, system_id, "timestamp", cpu_percent, cpu_temperature, ram_percent, disk_percent, disk_read_mbps, disk_write_mbps, network_sent_mbps, network_recv_mbps, gpu_percent, gpu_memory_used_gb, gpu_temperature, uptime_seconds, logged_in_users, cpu_iowait_percent, context_switch_rate, swap_in_rate, swap_out_rate, page_fault_rate, major_page_fault_rate) FROM stdin;
\.


--
-- Data for Name: _hyper_13_2_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._hyper_13_2_chunk (metric_id, system_id, "timestamp", cpu_percent, cpu_temperature, ram_percent, disk_percent, disk_read_mbps, disk_write_mbps, network_sent_mbps, network_recv_mbps, gpu_percent, gpu_memory_used_gb, gpu_temperature, uptime_seconds, logged_in_users, cpu_iowait_percent, context_switch_rate, swap_in_rate, swap_out_rate, page_fault_rate, major_page_fault_rate) FROM stdin;
\.


--
-- Data for Name: _hyper_13_3_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._hyper_13_3_chunk (metric_id, system_id, "timestamp", cpu_percent, cpu_temperature, ram_percent, disk_percent, disk_read_mbps, disk_write_mbps, network_sent_mbps, network_recv_mbps, gpu_percent, gpu_memory_used_gb, gpu_temperature, uptime_seconds, logged_in_users, cpu_iowait_percent, context_switch_rate, swap_in_rate, swap_out_rate, page_fault_rate, major_page_fault_rate) FROM stdin;
\.


--
-- Data for Name: _hyper_13_4_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._hyper_13_4_chunk (metric_id, system_id, "timestamp", cpu_percent, cpu_temperature, ram_percent, disk_percent, disk_read_mbps, disk_write_mbps, network_sent_mbps, network_recv_mbps, gpu_percent, gpu_memory_used_gb, gpu_temperature, uptime_seconds, logged_in_users, cpu_iowait_percent, context_switch_rate, swap_in_rate, swap_out_rate, page_fault_rate, major_page_fault_rate) FROM stdin;
\.


--
-- Data for Name: _hyper_17_14_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._hyper_17_14_chunk (system_id, hour_bucket, avg_cpu_percent, max_cpu_percent, min_cpu_percent, p95_cpu_percent, stddev_cpu_percent, avg_ram_percent, max_ram_percent, p95_ram_percent, stddev_ram_percent, avg_gpu_percent, max_gpu_percent, stddev_gpu_percent, avg_disk_percent, max_disk_percent, stddev_disk_percent, metric_count) FROM stdin;
1	2025-12-30 13:30:00+05:30	0.69692307692307692308	5.49	0.00	3.5819999999999954	1.5652230118813986	13.3953846153846154	14.96	14.81	1.7295115658503867	0.07692307692307692308	1.00	0.27735009811261456101	9.0000000000000000	9.00	0	13
1	2025-12-31 10:30:00+05:30	0.29037735849056603774	3.41	0.00	1.7939999999999992	0.66907502817222036463	11.6962264150943396	12.53	12.146	0.75237885918622331045	0.03773584905660377358	1.00	0.19238024756109730516	9.0000000000000000	9.00	0	53
1	2025-12-31 11:30:00+05:30	0.17301507537688442211	5.69	0.00	0.45199999999999935	0.58422784642574335820	11.8461809045226131	13.30	12.41	0.27367954319019510584	0.04020100502512562814	3.00	0.29880563561916415416	9.0000000000000000	9.00	0	199
1	2025-12-31 12:30:00+05:30	0.06268656716417910448	0.56	0.00	0.2139999999999995	0.09017797368557960279	11.7579104477611940	11.97	11.937	0.09144525292834946017	0.00000000000000000000	0.00	0	9.0000000000000000	9.00	0	67
\.


--
-- Data for Name: _hyper_17_15_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._hyper_17_15_chunk (system_id, hour_bucket, avg_cpu_percent, max_cpu_percent, min_cpu_percent, p95_cpu_percent, stddev_cpu_percent, avg_ram_percent, max_ram_percent, p95_ram_percent, stddev_ram_percent, avg_gpu_percent, max_gpu_percent, stddev_gpu_percent, avg_disk_percent, max_disk_percent, stddev_disk_percent, metric_count) FROM stdin;
1	2026-01-07 12:30:00+05:30	7.3937179487179487	8.46	6.35	8.094999999999999	0.43908437485873742384	22.9217948717948718	23.09	23.01	0.05083059692497800827	3.1410256410256410	4.00	0.35030076036260999047	9.0000000000000000	9.00	0	78
1	2026-01-07 17:30:00+05:30	4.2260909090909091	24.05	0.00	9.615499999999999	4.1952244793367957	19.5608181818181818	28.52	28.26	6.2777950216307113	2.4272727272727273	28.00	4.1296846424440650	9.0000000000000000	9.00	0	110
\.


--
-- Data for Name: _hyper_17_16_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._hyper_17_16_chunk (system_id, hour_bucket, avg_cpu_percent, max_cpu_percent, min_cpu_percent, p95_cpu_percent, stddev_cpu_percent, avg_ram_percent, max_ram_percent, p95_ram_percent, stddev_ram_percent, avg_gpu_percent, max_gpu_percent, stddev_gpu_percent, avg_disk_percent, max_disk_percent, stddev_disk_percent, metric_count) FROM stdin;
1	2026-01-20 10:30:00+05:30	0.07000000000000000000	0.31	0.00	0.2529999999999999	0.11532562594670795889	9.4742857142857143	9.63	9.621	0.10564991605252112977	0.00000000000000000000	0.00	0	9.0000000000000000	9.00	0	7
1	2026-01-20 11:30:00+05:30	19.1602675585284281	100.00	0.00	100	39.3019143179526178	11.1277257525083612	12.96	12.19	1.1854334770718983	0.22742474916387959866	4.00	0.50011782858909536123	9.0000000000000000	9.00	0	299
1	2026-01-20 12:30:00+05:30	17.2472809667673716	100.00	0.00	100	36.6213705349374123	14.9991540785498489	21.77	19.945	3.2412215070874194	15.9637462235649547	96.00	30.5130655052772722	9.0000000000000000	9.00	0	331
1	2026-01-20 13:30:00+05:30	1.3686138613861386	8.73	0.00	3.1364999999999994	1.09698005143199476717	20.9413366336633663	25.83	25.218	2.8214048043826654	1.4603960396039604	18.00	2.5860159414314273	9.0000000000000000	9.00	0	202
1	2026-01-20 14:30:00+05:30	0.13704225352112676056	1.38	0.00	1.065	0.31420372993238085228	18.4429577464788732	18.85	18.705	0.11838670734017858717	0.07042253521126760563	2.00	0.30817173607175737444	9.0000000000000000	9.00	0	71
3	2026-01-20 11:30:00+05:30	11.0915767634854772	41.58	0.00	40.78	17.8116750102320383	17.2283817427385892	17.81	17.52	0.27019027924523279218	\N	\N	\N	10.0000000000000000	10.00	0	241
3	2026-01-20 12:30:00+05:30	0.07265861027190332326	0.65	0.00	0.3	0.10603116212842914748	17.1036858006042296	17.36	17.17	0.04464348075053912292	\N	\N	\N	10.0000000000000000	10.00	0	331
3	2026-01-20 13:30:00+05:30	0.08078817733990147783	0.65	0.00	0.35	0.11699779746648224330	17.1922167487684729	17.29	17.24	0.02776336205407193025	\N	\N	\N	10.0000000000000000	10.00	0	203
3	2026-01-20 14:30:00+05:30	0.10704225352112676056	0.85	0.00	0.375	0.15149157794786748095	17.2202816901408451	17.26	17.25	0.02083759178476078075	\N	\N	\N	10.0000000000000000	10.00	0	71
\.


--
-- Data for Name: _hyper_18_17_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._hyper_18_17_chunk (system_id, day_bucket, avg_cpu_percent, max_cpu_percent, min_cpu_percent, p95_cpu_percent, stddev_cpu_percent, avg_ram_percent, max_ram_percent, min_ram_percent, p95_ram_percent, stddev_ram_percent, avg_gpu_percent, max_gpu_percent, min_gpu_percent, stddev_gpu_percent, avg_disk_percent, max_disk_percent, min_disk_percent, stddev_disk_percent, metric_count) FROM stdin;
1	2025-12-30 05:30:00+05:30	0.69692307692307692308	5.49	0.00	3.5819999999999954	1.5652230118813986	13.3953846153846154	14.96	9.62	14.81	1.7295115658503867	0.07692307692307692308	1.00	0.00	0.27735009811261456101	9.0000000000000000	9.00	9.00	0	13
1	2025-12-31 05:30:00+05:30	0.16934169278996865204	5.69	0.00	0.44599999999999795	0.54060925843003290641	11.8027272727272727	13.30	9.07	12.381	0.38004272878243602662	0.03134796238244514107	3.00	0.00	0.24881176977873505217	9.0000000000000000	9.00	9.00	0	319
\.


--
-- Data for Name: _hyper_18_18_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._hyper_18_18_chunk (system_id, day_bucket, avg_cpu_percent, max_cpu_percent, min_cpu_percent, p95_cpu_percent, stddev_cpu_percent, avg_ram_percent, max_ram_percent, min_ram_percent, p95_ram_percent, stddev_ram_percent, avg_gpu_percent, max_gpu_percent, min_gpu_percent, stddev_gpu_percent, avg_disk_percent, max_disk_percent, min_disk_percent, stddev_disk_percent, metric_count) FROM stdin;
1	2026-01-07 05:30:00+05:30	5.5403191489361702	24.05	0.00	8.4895	3.5758874451797171	20.9552659574468085	28.52	9.66	28.2365	5.0724716241775315	2.7234042553191489	28.00	0.00	3.1805029546063733	9.0000000000000000	9.00	9.00	0	188
\.


--
-- Data for Name: _hyper_18_19_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._hyper_18_19_chunk (system_id, day_bucket, avg_cpu_percent, max_cpu_percent, min_cpu_percent, p95_cpu_percent, stddev_cpu_percent, avg_ram_percent, max_ram_percent, min_ram_percent, p95_ram_percent, stddev_ram_percent, avg_gpu_percent, max_gpu_percent, min_gpu_percent, stddev_gpu_percent, avg_disk_percent, max_disk_percent, min_disk_percent, stddev_disk_percent, metric_count) FROM stdin;
1	2026-01-20 05:30:00+05:30	12.8840109890109890	100.00	0.00	100	32.5091926757143847	15.2723406593406593	25.83	9.29	24.038499999999996	4.4608533070543656	6.2109890109890110	96.00	0.00	19.8555146814985847	9.0000000000000000	9.00	9.00	0	910
3	2026-01-20 05:30:00+05:30	3.2164539007092199	41.58	0.00	40.58	10.7168813114373190	17.1702364066193853	17.81	16.73	17.47	0.15734916782054456407	\N	\N	\N	\N	10.0000000000000000	10.00	10.00	0	846
\.


--
-- Data for Name: _materialized_hypertable_17; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._materialized_hypertable_17 (system_id, hour_bucket, avg_cpu_percent, max_cpu_percent, min_cpu_percent, p95_cpu_percent, stddev_cpu_percent, avg_ram_percent, max_ram_percent, p95_ram_percent, stddev_ram_percent, avg_gpu_percent, max_gpu_percent, stddev_gpu_percent, avg_disk_percent, max_disk_percent, stddev_disk_percent, metric_count) FROM stdin;
\.


--
-- Data for Name: _materialized_hypertable_18; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal._materialized_hypertable_18 (system_id, day_bucket, avg_cpu_percent, max_cpu_percent, min_cpu_percent, p95_cpu_percent, stddev_cpu_percent, avg_ram_percent, max_ram_percent, min_ram_percent, p95_ram_percent, stddev_ram_percent, avg_gpu_percent, max_gpu_percent, min_gpu_percent, stddev_gpu_percent, avg_disk_percent, max_disk_percent, min_disk_percent, stddev_disk_percent, metric_count) FROM stdin;
\.


--
-- Data for Name: compress_hyper_14_11_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal.compress_hyper_14_11_chunk (_ts_meta_count, system_id, metric_id, _ts_meta_min_1, _ts_meta_max_1, "timestamp", cpu_percent, cpu_temperature, ram_percent, disk_percent, disk_read_mbps, disk_write_mbps, network_sent_mbps, network_recv_mbps, gpu_percent, gpu_memory_used_gb, gpu_temperature, uptime_seconds, logged_in_users, cpu_iowait_percent, context_switch_rate, swap_in_rate, swap_out_rate, page_fault_rate, major_page_fault_rate) FROM stdin;
13	1	BAAAAAAAAAAAAf//////////AAAADQAAAAIAAAAAAAAAFQAAAAAAAAN6AAAAAAAAAAA=	2025-12-30 13:30:44.310463+05:30	2025-12-30 13:35:49.850503+05:30	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	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAANAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAAC	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAANAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4=	BAAAAAAAAAA1m//////////dAAAADQAAAAIAAAAAAAAAawAAAABtt22aAAAAAA7UAEI=	BAAAAAAAAAAAAgAAAAAAAAAAAAAADQAAAAEAAAAAAAAAAwAAAAAAAAAc	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: compress_hyper_14_12_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal.compress_hyper_14_12_chunk (_ts_meta_count, system_id, metric_id, _ts_meta_min_1, _ts_meta_max_1, "timestamp", cpu_percent, cpu_temperature, ram_percent, disk_percent, disk_read_mbps, disk_write_mbps, network_sent_mbps, network_recv_mbps, gpu_percent, gpu_memory_used_gb, gpu_temperature, uptime_seconds, logged_in_users, cpu_iowait_percent, context_switch_rate, swap_in_rate, swap_out_rate, page_fault_rate, major_page_fault_rate) FROM stdin;
319	1	BAAAAAAAAAAADv//////////AAABPwAAAAQAAAAAAAD2+QAAAAAACv6+AAAJ4AAAAAAAAAAAAAAJpQAACRAAAAAA	2025-12-31 11:17:08.776466+05:30	2025-12-31 12:46:09.779308+05:30	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/wAAAAIMHAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACBLAAAAAKAAH//wAAAAIHbAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIYnAAAAAoAAf//AAAAAhXgAAAADAACAAAAAAACAAEa9AAAAAoAAf//AAAAAgwcAAAACgAB//8AAAACBLAAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACBLAAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAhXgAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIFFAAAAAoAAf//AAAAAgJYAAAADAACAAAAAAACAAQRMAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIEsAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgUUAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIJxAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIHbAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgSwAAAACgAB//8AAAACB2wAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAgdsAAAACgAB//8AAAACBLAAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgSwAAAACAAAAAAAAAACAAAADAACAAAAAAACAAUa9AAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACB2wAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAgdsAAAACgAB//8AAAACBLAAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIHbAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIEsAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgdsAAAACAAAAAAAAAACAAAACgAB//8AAAACCcQAAAAKAAH//wAAAAIJxAAAAAoAAf//AAAAAhr0AAAADAACAAAAAAACAAMcIAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgUUAAAACgAB//8AAAACBRQAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgUUAAAACgAB//8AAAACB2wAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgdsAAAACAAAAAAAAAACAAAACgAB//8AAAACBRQAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACBRQAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACBRQAAAAKAAH//wAAAAIHbAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIHbAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACBRQAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgUUAAAACgAB//8AAAACB2wAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgdsAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgSwAAAACgAB//8AAAACB2wAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACBLAAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAhEwAAAACgAB//8AAAACBLAAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgdsAAAACgAB//8AAAACCcQAAAAKAAH//wAAAAIfpAAAAAoAAf//AAAAAgSwAAAACgAB//8AAAACCcQAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACBLAAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACgAB//8AAAACB2wAAAAKAAH//wAAAAIFFAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACBRQAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgSwAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIEsAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAhXgAAAACgAB//8AAAACB2wAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACCcQAAAAKAAH//wAAAAIFFAAAAAoAAf//AAAAAgdsAAAACgAB//8AAAACB2wAAAAKAAH//wAAAAIHbAAAAAoAAf//AAAAAgSwAAAACgAB//8AAAACCcQAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAKAAH/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AAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAMAAIAAAAAAAIAIBtYAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAwAAgAAAAAAAgAgC7gAAAAMAAIAAAAAAAIAIAu4AAAADAACAAAAAAACACAD6AAAAAwAAgAAAAAAAgAgA+gAAAAMAAIAAAAAAAIAIAfQAAAADAACAAAAAAACACATiAAAAAwAAgAAAAAAAgAgB9AAAAAMAAIAAAAAAAIAIAu4AAAADAACAAAAAAACACALuAAAAAwAAgAAAAAAAgAgE4gAAAAMAAIAAAAAAAIAIAu4AAAADAACAAAAAAACACALuAAAAAwAAgAAAAAAAgAgC7gAAAAMAAIAAAAAAAIAIBdwAAAADAACAAAAAAACACAbWAAAAAwAAgAAAAAAAgAhB9AAAAAMAAIAAAAAAAIAIBtYAAAADAACAAAAAAACACALuAAAAAwAAgAAAAAAAgAjA+gAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAMAAIAAAAAAAIAIAfQAAAADAACAAAAAAACACAD6AAAAAwAAgAAAAAAAgAgG1gAAAAMAAIAAAAAAAIAIAPoAAAADAACAAAAAAACACAD6AAAAAwAAgAAAAAAAgAgA+gAAAAMAAIAAAAAAAIAIBdwAAAADAACAAAAAAACACALuAAAAAwAAgAAAAAAAgAiB9AAAAAMAAIAAAAAAAIALBOIAAAADAACAAAAAAACACALuAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAwAAgAAAAAAAgAgB9AAAAAMAAIAAAAAAAIAHx9AAAAACgABAAAAAAACACAAAAAMAAIAAAAAAAIAIAPoAAAADAACAAAAAAACACAH0AAAAAwAAgAAAAAAAgAgA+gAAAAMAAIAAAAAAAIAIAPoAAAADAACAAAAAAACACAH0AAAAAwAAgAAAAAAAgAgC7gAAAAMAAIAAAAAAAIAIAPoAAAADAACAAAAAAACACALuAAAAAwAAgAAAAAAAgAgC7gAAAAMAAIAAAAAAAIAIAu4AAAADAACAAAAAAACACAH0AAAAAwAAgAAAAAAAgAgB9AAAAAMAAIAAAAAAAIAIBdwAAAADAACAAAAAAACACALuAAAAAoAAQAAAAAAAgAhAAAADAACAAAAAAACACETiAAAAAwAAgAAAAAAAgAhA+gAAAAMAAIAAAAAAAIAKhOIAAAADAACAAAAAAACACAbWAAAAAwAAgAAAAAAAgAgC7gAAAAMAAIAAAAAAAIAIBOIAAAADAACAAAAAAACACIH0AAAAAwAAgAAAAAAAgAvF3AAAAAMAAIAAAAAAAIAIAPoAAAADAACAAAAAAACACAD6AAAAAwAAgAAAAAAAgAgB9AAAAAMAAIAAAAAAAIAIAu4AAAADAACAAAAAAACACAD6AAAAAwAAgAAAAAAAgAgB9AAAAAMAAIAAAAAAAIAIAu4AAAADAACAAAAAAACACALuAAAAAwAAgAAAAAAAgAgC7gAAAAMAAIAAAAAAAIAIAu4AAAADAACAAAAAAACACALuAAAAAwAAgAAAAAAAgAgE4gAAAAMAAIAAAAAAAIAIAu4AAAADAACAAAAAAACACATiAAAAAwAAgAAAAAAAgAgE4gAAAAMAAIAAAAAAAIAIBdwAAAADAACAAAAAAACACELuAAAAAwAAgAAAAAAAgAgG1gAAAAMAAIAAAAAAAIAIB9AAAAADAACAAAAAAACACED6AAAAAwAAgAAAAAAAgAhF3AAAAAMAAIAAAAAAAIAIROIAAAADAACAAAAAAACACMLuAAAAAwAAgAAAAAAAgAhA+gAAAAKAAEAAAAAAAIAIAAAAAwAAgAAAAAAAgAfH0AAAAAMAAIAAAAAAAIAHx9AAAAADAACAAAAAAACAB8fQAAAAAwAAgAAAAAAAgAfH0AAAAAMAAIAAAAAAAIAHxtYAAAADAACAAAAAAACAB8bWAAAAAwAAgAAAAAAAgAfH0AAAAAMAAIAAAAAAAIAHxtYAAAADAACAAAAAAACACAH0AAAAAwAAgAAAAAAAgAfG1gAAAAMAAIAAAAAAAIAHxtYAAAADAACAAAAAAACAB8fQAAAAAwAAgAAAAAAAgAfF3AAAAAMAAIAAAAAAAIAHxtYAAAADAACAAAAAAACACAD6AAAAAwAAgAAAAAAAgAfB9AAAAAMAAIAAAAAAAIAHxtYAAAACgABAAAAAAACACEAAAAMAAIAAAAAAAIAHxdwAAAADAACAAAAAAACAB8TiAAAAAwAAgAAAAAAAgAfE4gAAAAMAAIAAAAAAAIAHxOIAAAADAACAAAAAAACAB8TiAAAAAwAAgAAAAAAAgAfE4gAAAAMAAIAAAAAAAIAHxOIAAAADAACAAAAAAACAB8H0AAAAAwAAgAAAAAAAgAfE4gAAAAMAAIAAAAAAAIAHwu4AAAADAACAAAAAAACAB8bWAAAAAwAAgAAAAAAAgAiA+gAAAAMAAIAAAAAAAIAHwfQAAAADAACAAAAAAACAB8H0AAAAAwAAgAAAAAAAgAfC7gAAAAMAAIAAAAAAAIAHwu4AAAADAACAAAAAAACAB8H0AAAAAwAAgAAAAAAAgAfE4gAAAAMAAIAAAAAAAIAHwu4AAAADAACAAAAAAACAB8LuAAAAAwAAgAAAAAAAgAfC7gAAAAMAAIAAAAAAAIAHxOIAAAADAACAAAAAAACAB8LuAAAAAwAAgAAAAAAAgAfC7gAAAAMAAIAAAAAAAIAHxOIAAAACgABAAAAAAACACAAAAAMAAIAAAAAAAIAJBtYAAAADAACAAAAAAACAB8H0AAAAAwAAgAAAAAAAgAfC7gAAAAMAAIAAAAAAAIAHwfQAAAADAACAAAAAAACAB8LuAAAAAwAAgAAAAAAAgAfC7gAAAAMAAIAAAAAAAIAHwu4AAAADAACAAAAAAACAB8H0AAAAAwAAgAAAAAAAgAfC7gAAAAMAAIAAAAAAAIAHwu4AAAADAACAAAAAAACAB8LuAAAAAwAAgAAAAAAAgAfB9AAAAAMAAIAAAAAAAIAHwfQAAAADAACAAAAAAACAB8LuAAAAAwAAgAAAAAAAgAfC7gAAAAMAAIAAAAAAAIAHwfQAAAADAACAAAAAAACAB8H0AAAAAwAAgAAAAAAAgAfB9AAAAAMAAIAAAAAAAIAHwu4AAAADAACAAAAAAACAB8H0AAAAAwAAgAAAAAAAgAfB9AAAAAMAAIAAAAAAAIAHwu4AAAADAACAAAAAAACAB8H0AAAAAwAAgAAAAAAAgAfB9AAAAAMAAIAAAAAAAIAHwu4AAAADAACAAAAAAACAB8H0AAAAAwAAgAAAAAAAgAfC7gAAAAMAAIAAAAAAAIAHxOIAAAADAACAAAAAAACAB8LuAAAAAwAAgAAAAAAAgAfB9AAAAAMAAIAAAAAAAIAHwu4AAAADAACAAAAAAACAB8TiAAAAAwAAgAAAAAAAgAgA+gAAAAMAAIAAAAAAAIAHxOIAAAA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AQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAk=	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAE/AAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4QAAAAKAAH//0AAAAIDhAAAAAoAAf//QAAAAgOEAAAACgAB//9AAAACA4Q=	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAE/AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuA==	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAE/AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAoAAf//AAAAAg7YAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICvAAAAAwAAgAAAAAAAgAIDOQAAAAMAAIAAAAAAAIAAiRUAAAACgAB//8AAAACAyAAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIDhAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAIBLAAAAAwAAgAAAAAAAgAHGpAAAAAMAAIAAAAAAAIAAwdsAAAADAACAAAAAAACAAIB9AAAAAwAAgAAAAAAAgACF9QAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAI=	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAE/AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAMAAIAAAAAAAIAARDMAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACAyAAAAAKAAH//wAAAAIJYAAAAAwAAgAAAAAAAgBgHCAAAAAKAAH//wAAAAIM5AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgDIAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAADAACAAAAAAACAAIbvAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACgAB//8AAAACAMgAAAAKAAH//wAAAAIRMAAAAAoAAf//AAAAAgzkAAAADAACAAAAAAACAEcYnAAAAAwAAgAAAAAAAgBMDUgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAI=	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAE/AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgABAAAAAAACAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgABAAAAAAACAAMAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAAC	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAE/AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAAC	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAE/AAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACEAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACEAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACEAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACABwAAAAKAAEAAAAAAAIAHAAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB4=	BAAAAAAAAAAAbf/////////xAAABPwAAAAwAACIiKiIiKwABAAIqsSqUmZhmZmZmZmZmZmZhmZmZmWZmZmZmZmZmSGZmZmZmZmZmZmZmZmZmZgACABACWIWHZmZhmZIZmZmZmYZmZmZmZoGBgYYZmZmZgYGBgYGBgYEAAAAYAGGBgQ==	BAAAAAAAAAAAAgAAAAAAAAAAAAABPwAAAAIAAAAAAAAA8wAAAAAAAAAcAAASoAAAAAA=	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: compress_hyper_14_13_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal.compress_hyper_14_13_chunk (_ts_meta_count, system_id, metric_id, _ts_meta_min_1, _ts_meta_max_1, "timestamp", cpu_percent, cpu_temperature, ram_percent, disk_percent, disk_read_mbps, disk_write_mbps, network_sent_mbps, network_recv_mbps, gpu_percent, gpu_memory_used_gb, gpu_temperature, uptime_seconds, logged_in_users, cpu_iowait_percent, context_switch_rate, swap_in_rate, swap_out_rate, page_fault_rate, major_page_fault_rate) FROM stdin;
188	1	BAAAAAAAAAABzv//////////AAAAvAAAAAQAAAAAAAD5+QAAAAAADm+aAAAGgAAAAAAAAAAAAAXdeAAABIAAAAAA	2026-01-07 12:41:22.65817+05:30	2026-01-07 18:11:09.932272+05:30	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AAAMAAIAAAAAAAIAKxdwAAAADAACAAAAAAACACkTiAAAAAwAAgAAAAAAAgAnC7gAAAAMAAIAAAAAAAIAIAfQAAAADAACAAAAAAACACAfQAAAAAwAAgAAAAAAAgAgC7gAAAAMAAIAAAAAAAIAIBdwAAAADAACAAAAAAACACAfQAAAAAoAAQAAAAAAAgAiAAAADAACAAAAAAACACAbWAAAAAwAAgAAAAAAAgAiE4gAAAAMAAIAAAAAAAIAIQu4AAAADAACAAAAAAACACEH0AAAAAoAAQAAAAAAAgAgAAAADAACAAAAAAACACAD6AAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACIAAAAMAAIAAAAAAAIAIwPoAAAADAACAAAAAAACACUD6AAAAAwAAgAAAAAAAgAfH0AAAAAMAAIAAAAAAAIAHwfQAAAACgABAAAAAAACACAAAAAMAAIAAAAAAAIAHh9AAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeE4gAAAAMAAIAAAAAAAIAHh9AAAAACgABAAAAAAACAB8AAAAMAAIAAAAAAAIAHhOIAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAfA+gAAAAMAAIAAAAAAAIAHhOIAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeH0AAAAAMAAIAAAAAAAIAHwPoAAAADAACAAAAAAACAB8H0AAAAAoAAQAAAAAAAgAgAAAADAACAAAAAAACACMbWAAAAAwAAgAAAAAAAgAqE4gAAAAMAAIAAAAAAAIAHR9AAAAADAACAAAAAAACAB0H0AAAAAwAAgAAAAAAAgAdC7gAAAAMAAIAAAAAAAIAHQPoAAAADAACAAAAAAACAB0D6AAAAAwAAgAAAAAAAgAdA+gAAAAMAAIAAAAAAAIAHQfQAAAADAACAAAAAAACAB0H0AAAAAwAAgAAAAAAAgAdB9AAAAAMAAIAAAAAAAIAHRdwAAAADAACAAAAAAACAB0D6AAAAAwAAgAAAAAAAgAdE4gAAAAMAAIAAAAAAAIAHQPoAAAADAACAAAAAAACAB0H0AAAAAwAAgAAAAAAAgAdC7gAAAAMAAIAAAAAAAIAHR9AAAAADAACAAAAAAACACQbWAAAAAwAAgAAAAAAAgBAB9AAAAAMAAIAAAAAAAIAQBdwAAAA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AQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQ==	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAC8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAglgAAAACgAB//8AAAACCWAAAAAKAAH//wAAAAIJYAAAAAoAAf//AAAAAglgAAAACgAB//8AAAACCWAAAAAKAAH//wAAAAIJYAAAAAoAAf//AAAAAglgAAAACgAB//8AAAACCWAAAAAKAAH//wAAAAIJYAAAAAoAAf//AAAAAglgAAAACgAB//8AAAACCWAAAAAKAAH//wAAAAIJYAAAAAoAAf//AAAAAglgAAAACgAB//8AAAACCWAAAAAKAAH//wAAAAIJYAAAAAoAAf//AAAAAglgAAAACgAB//8AAAACCWAAAAAKAAH//wAAAAIJYAAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgj8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAII/A==	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAC8AAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEAwcAAAADAACAAAAAAACABAMHAAAAAwAAgAAAAAAAgAQDBwAAAAMAAIAAAAAAAIAEAwcAAAADAACAAAAAAACABAMHAAAAAwAAgAAAAAAAgAQDBwAAAAMAAIAAAAAAAIAEAwcAAAADAACAAAAAAACABAMHAAAAAwAAgAAAAAAAgAQDBwAAAAMAAIAAAAAAAIAEAwcAAAADAACAAAAAAACABAMHAAAAAwAAgAAAAAAAgAQDBwAAAAMAAIAAAAAAAIAEAwcAAAADAACAAAAAAACABAMHAAAAAwAAgAAAAAAAgAQDBwAAAAMAAIAAAAAAAIAEAwcAAAADAACAAAAAAACABAMHAAAAAwAAgAAAAAAAgAQDBwAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQAAAAMAAIAAAAAAAIAEwakAAAADAACAAAAAAACABMGpAAAAAwAAgAAAAAAAgATBqQ=	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAC8AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAZAAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgGQAAAACgAB//8AAAACA4QAAAAKAAH//wAAAAIGQAAAAAoAAf//AAAAAgXcAAAACgAB//8AAAACBXgAAAAKAAH//wAAAAIKjAAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIEsAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACCDQAAAAKAAH//wAAAAILVAAAAAoAAf//AAAAAgSwAAAACgAB//8AAAACEAQAAAAKAAH//wAAAAIMHAAAAAoAAf//AAAAAgakAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAADAACAAAAAAACAAIEsAAAAAoAAf//AAAAAiH8AAAADAACAAAAAAACAAIhmAAAAAwAAgAAAAAAAgABIygAAAAMAAIAAAAAAAIAAg7YAAAACgAB//8AAAACFwwAAAAKAAH//wAAAAIBkAAAAAoAAf//AAAAAgj8AAAACAAAAAAAAAACAAAACgAB//8AAAACHbAAAAAKAAH//wAAAAIBLAAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAMgAAAAKAAH//wAAAAIBLAAAAAwAAgAAAAAAAgACJRwAAAAKAAH//wAAAAII/AAAAAoAAf//AAAAAgEsAAAADAACAAAAAAACAAIT7AAAAAwAAgAAAAAAAgACEAQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAg88AAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIRlAAAAAoAAf//AAAAAgDIAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAyAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAg==	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAC8AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgXcAAAACgAB//8AAAACASwAAAAKAAH//wAAAAIO2AAAAAwAAgAAAAAAAgAFA+gAAAAMAAIAAAAAAAIAAx54AAAADAACAAAAAAACAAUF3AAAAAoAAf//AAAAAgDIAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgV4AAAADAACAAAAAAACAAYBLAAAAAoAAf//AAAAAgcIAAAADAACAAAAAAACAAcOdAAAAAwAAgAAAAAAAgACJFQAAAAKAAH//wAAAAIETAAAAAoAAf//AAAAAgDIAAAACgAB//8AAAACASwAAAAKAAH//wAAAAIAZAAAAAwAAgAAAAAAAgBCCvAAAAAMAAIAAAAAAAIAGx7cAAAADAACAAAAAAACAF0INAAAAAwAAgAAAAAAAgA8CcQAAAAMAAIAAAAAAAIASwlgAAAADAACAAAAAAACAA0lgAAAAAoAAf//AAAAAgV4AAAACgAB//8AAAACGpAAAAAKAAH//wAAAAIAZAAAAAwAAgAAAAAAAgAJCigAAAAKAAH//wAAAAIBLAAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAICvAAAAAoAAf//AAAAAgDIAAAACAAAAAAAAAACAAAADAACAAAAAAACAFse3AAAAAwAAgAAAAAAAgBFElwAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAwAAgAAAAAAAgACGDgAAAAMAAIAAAAAAAIACR1MAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAMAAIAAAAAAAIACh4UAAAACgAB//8AAAACA+gAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIBLAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgK8AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAAC	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAC8AAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIABAAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIABAAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIABAAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIABAAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIABAAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIABAAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIABAAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIABAAAAAoAAQAAAAAAAgADAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIAAwAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAQAAAAAAAgACAAAACgABAAAAAAACAAYAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIADQAAAAoAAQAAAAAAAgAEAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgABAAAAAAACAAMAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIAHAAAAAoAAQAAAAAAAgAcAAAACAAAAAAAAAACAAAACgABAAAAAAACAAEAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIABwAAAAoAAQAAAAAAAgAHAAAACgABAAAAAAACAAMAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIABAAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIABAAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIABAAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAM=	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAC8AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAAC	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAC8AAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAuAAAACgABAAAAAAACACwAAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACACwAAAAKAAEAAAAAAAIALAAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACACwAAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALAAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAsAAAACgABAAAAAAACACwAAAAKAAEAAAAAAAIALAAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACACwAAAAKAAEAAAAAAAIAKwAAAAoAAQAAAAAAAgArAAAACgABAAAAAAACACoAAAAKAAEAAAAAAAIAKgAAAAoAAQAAAAAAAgApAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJwAAAAoAAQAAAAAAAgAnAAAACgABAAAAAAACACkAAAAKAAEAAAAAAAIAKgAAAAoAAQAAAAAAAgApAAAACgABAAAAAAACACgAAAAKAAEAAAAAAAIAJwAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACIAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACEAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACEAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACIAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACMAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAcAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALgAAAAoAAQAAAAAAAgAuAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALgAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALgAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAuAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAuAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALgAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALgAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALAAAAAoAAQAAAAAAAgAuAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALgAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALwAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALAAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC0AAAAKAAEAAAAAAAIALQ==	BAAAAAAAAAAHKf/////////xAAAAvAAAAAkAAAACIrciKgACABAC5T42mZmZmZmZmZlhkhmZmZkmGWYZmZmYZmZmAgIICCAggIIAAQACFVEVUGZmZmZmYSZmmZmZmZmZhmYAAAAAAAZmGQ==	BAAAAAAAAAAAAgAAAAAAAAAAAAAAvAAAAAIAAAAAAAAA8wAAAAAAAAAcAAAKcAAAAAA=	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: compress_hyper_14_20_chunk; Type: TABLE DATA; Schema: _timescaledb_internal; Owner: aayush
--

COPY _timescaledb_internal.compress_hyper_14_20_chunk (_ts_meta_count, system_id, metric_id, _ts_meta_min_1, _ts_meta_max_1, "timestamp", cpu_percent, cpu_temperature, ram_percent, disk_percent, disk_read_mbps, disk_write_mbps, network_sent_mbps, network_recv_mbps, gpu_percent, gpu_memory_used_gb, gpu_temperature, uptime_seconds, logged_in_users, cpu_iowait_percent, context_switch_rate, swap_in_rate, swap_out_rate, page_fault_rate, major_page_fault_rate) FROM stdin;
910	1	BAAAAAAAAAACLv//////////AAADjgAAACIzMzIiIyIiKyIiMzMiMzMyAAAAAAAAABMAAAAAEhMSEAAAAC4AAAAAAuAAuAC4AC4AAAAAAAAAALgAAALi4AAAAAAAAAAAAAAAAAE40AAAAAALgAAAuAAAgAAALgALgAAAGLgALgAuJQAAAAAAAAAAJEwgAAAAAAAgAAAAAAAE4xhKRAKACJhBEwgwmNImNBFCUAiY40E40guAAC4LpYALBNAAABEGNAAAAAAAAAAAADQAAAARBjjQAAAJoAABNAIAE0AnHCUAAC66QYAuAAuA4lgAAAAC4LhGgE0AmgnGggATSaAACaTjRoBONBNAAAAAAE4QUiY0iQAAAAAYkBi4AAAAAAAAAAAkAAAAAAAAAAAAAAAAAAAAAABJoJxpNAAAAAAAAAAAAA==	2026-01-20 11:28:15.929562+05:30	2026-01-20 14:42:45.57956+05:30	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AAACAAAACgAB//8AAAACBLAAAAAKAAH//wAAAAIYnAAAAAoAAf//AAAAAgSwAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIEsAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgdsAAAACAAAAAAAAAACAAAACgAB//8AAAACBLAAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgSwAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAgUUAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACETAAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgdsAAAACgAB//8AAAACBLAAAAAKAAH//wAAAAIO2AAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIA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AAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACB2wAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACBLAAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgSwAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACCcQAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACBLAAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIEsAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAADAACAAAAAAACAAYCvAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgdsAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgSwAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIHbAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgSwAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIEsAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIHbAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgdsAAAACAAAAAAAAAACAAAACgAB//8AAAACBLAAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIEsAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACgAB//8AAAACE4gAAAAKAAH//wAAAAIOdAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgUUAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgSwAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIfpAAAAAwAAgAAAAAAAgADGJwAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgnEAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgSwAAAACgAB//8AAAACBLAAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgdsAAAACgAB//8AAAACCcQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIEsAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACBLAAAAAIAAAAAAAAAAIAAAAMAAIAAAAAAAIAAQyAAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAACgABAAAAAAACAGQAAAAKAAEAAAAAAAIAZAAAAAoAAQAAAAAAAgBkAAAADAACAAAAAAACAAERMAAAAAwAAgAAAAAAAgACEZQAAAAKAAH//wAAAAIYnAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACBLAAAAAKAAH//wAAAAICWAAAAAoAAf//AAAAAgSwAAAACgAB//8AAAACBLAAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAg7YAAAADAACAAAAAAACAAIYnAAAAAoAAf//AAAAAgnEAAAACgAB//8AAAACHUwAAAAKAAH//wAAAAIa9AAAAAoAAf//AAAAAhXgAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACBLAAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgSwAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACgAB//8A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AAAAAAIAHhdwAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeG1gAAAAMAAIAAAAAAAIAHxOIAAAADAACAAAAAAACAB4bWAAAAAwAAgAAAAAAAgAeG1gAAAAMAAIAAAAAAAIAHhtYAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAfB9AAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4bWAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4fQAAAAAwAAgAAAAAAAgAeG1gAAAAMAAIAAAAAAAIAHhtYAAAADAACAAAAAAACAB4fQAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAMAAIAAAAAAAIAIBOIAAAADAACAAAAAAACACUTiAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHgu4AAAADAACAAAAAAACAB4TiAAAAAwAAgAAAAAAAgAeE4gAAAAMAAIAAAAAAAIAHgu4AAAADAACAAAAAAACAB4TiAAAAAwAAgAAAAAAAgAeE4gAAAAMAAIAAAAAAAIAHhOIAAAADAACAAAAAAACAB4TiAAAAAwAAgAAAAAAAgAeE4gAAAAMAAIAAAAAAAIAHhOIAAAADAACAAAAAAACAB4TiAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeE4gAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4LuAAAAAwAAgAAAAAAAgAeC7gAAAAMAAIAAAAAAAIAHgu4AAAADAACAAAAAAACAB4LuAAAAAwAAgAAAAAAAgAeC7gAAAAMAAIAAAAAAAIAHgu4AAAADAACAAAAAAACAB4TiAAAAAwAAgAAAAAAAgAeE4gAAAAMAAIAAAAAAAIAHhOIAAAADAACAAAAAAACAB4LuAAAAAwAAgAAAAAAAgAeC7gAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeE4gAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4TiAAAAAwAAgAAAAAAAgAeE4gAAAAMAAIAAAAAAAIAHhOIAAAADAACAAAAAAACAB4LuAAAAAwAAgAAAAAAAgAeC7gAAAAMAAIAAAAAAAIAHhOIAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhOIAAAADAACAAAAAAACAB4TiAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhOIAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhOIAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeE4gAAAAMAAIAAAAAAAIAHhOIAAAADAACAAAAAAACAB4TiAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4TiAAAAAwAAgAAAAAAAgAeE4gAAAAMAAIAAAAAAAIAHhOIAAAADAACAAAAAAACAB4TiAAAAAwAAgAAAAAAAgAeE4gAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4TiAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4XcAAAAAwAAgAAAAAAAgAeF3AAAAAMAAIAAAAAAAIAHhdwAAAADAACAAAAAAACAB4bWAAAAAwAAgAAAAAAAgAeG1gAAAAMAAIAAAAAAAIAHhtYAAAADAACAAAAAAACAB4bWAAAAAwAAgAAAAAAAgAfA+gAAAAMAAIAAAAAAAIAHhtYAAAADAACAAAAAAACAB4bWAAAAAwAAgAAAAAAAgAeG1gAAAAMAAIAAAAAAAIAHhtYAAAADAACAAAAAAACAB4fQAAAAAwAAgAAAAAAAgAeH0AAAAAMAAIAAAAAAAIAHhdwAAAA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AAAMAAIAAAAAAAIACyJgAAAADAACAAAAAAACAAshmAAAAAwAAgAAAAAAAgALImAAAAAMAAIAAAAAAAIACyAIAAAADAACAAAAAAACAAshmAAAAAwAAgAAAAAAAgALIygAAAAMAAIAAAAAAAIACyAIAAAADAACAAAAAAACAAsixAAAAAwAAgAAAAAAAgALHngAAAAMAAIAAAAAAAIACyAIAAAADAACAAAAAAACAAsh/AAAAAwAAgAAAAAAAgALI4wAAAAMAAIAAAAAAAIACyBsAAAADAACAAAAAAACAAseFAAAAAwAAgAAAAAAAgALITQAAAAMAAIAAAAAAAIACyGYAAAADAACAAAAAAACAAsfpAAAAAwAAgAAAAAAAgALImAAAAAMAAIAAAAAAAIACyPwAAAADAACAAAAAAACAAsfpAAAAAwAAgAAAAAAAgALIAgAAAAMAAIAAAAAAAIACx+kAAAADAACAAAAAAACAAshNAAAAAwAAgAAAAAAAgALINAAAAAMAAIAAAAAAAIACx+kAAAADAACAAAAAAACAAsj8AAAAAwAAgAAAAAAAgALJeQAAAAMAAIAAAAAAAIACyS4AAAADAACAAAAAAACAAsj8AAAAAwAAgAAAAAAAgALImAAAAAMAAIAAAAAAAIACyE0AAAADAACAAAAAAACAAsixAAAAAwAAgAAAAAAAgALIfwAAAAMAAIAAAAAAAIACyBsAAAADAACAAAAAAACAAshmAAAAAwAAgAAAAAAAgALIygAAAAMAAIAAAAAAAIACyAIAAAADAACAAAAAAACAAsixAAAAAwAAgAAAAAAAgALIfwAAAAMAAIAAAAAAAIACyGYAAAADAACAAAAAAACAAsgbAAAAAwAAgAAAAAAAgALJqwAAAAMAAIAAAAAAAIACyJgAAAADAACAAAAAAACAAslHAAAAAwAAgAAAAAAAgALITQAAAAMAAIAAAAAAAIACyAIAAAADAACAAAAAAACAAsg0AAAAAwAAgAAAAAAAgALIsQAAAAMAAIAAAAAAAIACyE0AAAADAACAAAAAAACAAsfQAAAAAwAAgAAAAAAAgALIfwAAAAMAAIAAAAAAAIACx9AAAAADAACAAAAAAACAAsfpAAAAAwAAgAAAAAAAgALIGwAAAAMAAIAAAAAAAIACx7cAAAADAACAAAAAAACAAsgCAAAAAwA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AgAJD6AAAAAMAAIAAAAAAAIACQ50AAAADAACAAAAAAACAAkOEAAAAAwAAgAAAAAAAgAJEMwAAAAMAAIAAAAAAAIACQtUAAAADAACAAAAAAACAAkM5AAAAAwAAgAAAAAAAgAJDBwAAAAMAAIAAAAAAAIACQ50AAAADAACAAAAAAACAAkNSAAAAAwAAgAAAAAAAgAJDtgAAAAMAAIAAAAAAAIACQzkAAAADAACAAAAAAACAAkO2AAAAAwAAgAAAAAAAgAJEZQAAAAMAAIAAAAAAAIACQ+gAAAADAACAAAAAAACAAkQzAAAAAwAAgAAAAAAAgAJDtgAAAAMAAIAAAAAAAIACQ7YAAAADAACAAAAAAACAAkO2AAAAAwAAgAAAAAAAgAJDhAAAAAMAAIAAAAAAAIACQ2sAAAADAACAAAAAAACAAkPPAAAAAwAAgAAAAAAAgAJDawAAAAMAAIAAAAAAAIACQ7YAAAADAACAAAAAAACAAkNSAAAAAwAAgAAAAAAAgAJDUgAAAAMAAIAAAAAAAIACQ88AAAADAACAAAAAAACAAkPPAAAAAwAAgAAAAAAAgAJDawAAAAMAAIAAAAAAAIACQyAAAAADAACAAAAAAACAAkPPAAAAAwAAgAAAAAAAgAJDOQAAAAMAAIAAAAAAAIACQ2sAAAADAACAAAAAAACAAkOdAAAAAwAAgAAAAAAAgAJEGgAAAAMAAIAAAAAAAIACRAEAAAADAACAAAAAAACAAkQBAAAAAwAAgAAAAAAAgAJDzwAAAAMAAIAAAAAAAIACRDMAAAADAACAAAAAAACAAkNSAAAAAwAAgAAAAAAAgAJDawAAAAMAAIAAAAAAAIACRAEAAAADAACAAAAAAACAAkNSAAAAAwAAgAAAAAAAgAJDawAAAAMAAIAAAAAAAIACQyAAAAADAACAAAAAAACAAkNSAAAAAwAAgAAAAAAAgAJDUgAAAAMAAIAAAAAAAIACQ2sAAAADAACAAAAAAACAAkMHAAAAAwAAgAAAAAAAgAJC7gAAAAMAAIAAAAAAAIACQ2sAAAADAACAAAAAAACAAkM5AAAAAwAAgAAAAAAAgAJDBwAAAAMAAIAAAAAAAIACQ1IAAAADAACAAAAAAACAAkM5AAAAAwAAgAAAAAAAgAJDOQAAAAMAAIAAAAAAAIACQ50AAAADAACAAAAAAACAAkPoAAAAAwAAgAAAAAAAgAJDhAAAAAMAAIAAAAAAAIACQ4QAAAADAACAAAAAAACAAkOEAAAAAwAAgAAAAAAAgAJDBwAAAAMAAIAAAAAAAIACQzkAAAADAACAAAAAAACAAkQaAAAAAwAAgAAAAAAAgAJEMwAAAAMAAIAAAAAAAIACREwAAAADAACAAAAAAACAAkSXAAAAAwAAgAAAAAAAgAJGJwAAAAMAAIAAAAAAAIACRdw	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAOOAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAkAAAAKAAEAAAAAAAIACQAAAAoAAQAAAAAAAgAJAAAACgABAAAAAAACAAk=	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAOOAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACASwAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAyAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAg88AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAMgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIImAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoAAf//QAAAAgMgAAAACgAB//9AAAACAyAAAAAKAAH//0AAAAIDIAAAAAoA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uAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuAAAAAwAAgAAQAAAAgAKC7gAAAAMAAIAAEAAAAIACgu4AAAADAACAABAAAACAAoLuA==	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAOOAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAZAAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAZAAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAICvAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACBLAAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACA+gAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIRlAAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACFqgAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACAyAAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIBLAAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIGQAAAAAoAAf//AAAAAgDIAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAIEsAAAAAoAAf//AAAAAgV4AAAACgAB//8AAAACDhAAAAAKAAH//wAAAAIGpAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACArwAAAAKAAH//wAAAAIAyAAAAAoAAf//AAAAAgOEAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIINAAAAAoAAf//AAAAAg4QAAAACgAB//8AAAACBRQAAAAKAAH//wAAAAIBLAAAAAoAAf//AAAAAgDIAAAACgAB//8AAAACA4QAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAICvAAAAAoAAf//AAAAAgDIAAAACgAB//8AAAACCJgAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIGpAAAAAoAAf//AAAAAgEsAAAACgAB//8AAAACB2wAAAAKAAH//wAAAAIRlAAAAAoAAf//AAAAAgUUAAAACgAB//8AAAACBkAAAAAKAAH//wAAAAIHCAAAAAoAAf//AAAAAgEsAAAACgAB//8AAAACASwAAAAKAAH//wAAAAIBkAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgGQAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIBkAAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAyAAAAAKAAH//wAAAAIBLAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACASwAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAyAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAg1IAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAIAyAAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACAMgAAAAKAAH//wAAAAIBLAAAAAoAAf//AAAAAgDIAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAIAZAAAAAoAAf//AAAAAgDIAAAACAAAAAAAAAACAAAACgAB//8AAAACBRQAAAAKAAH//wAAAAIETAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgEsAAAACgAB//8AAAACASwAAAAKAAH//wAAAAIHCAAAAAoAAf//AAAAAgRMAAAACgAB//8AAAACC1QAAAAKAAH//wAAAAIDhAAAAAoAAf//AAAAAgGQAAAACgAB//8AAAACAlgAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACEMwAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIBLAAAAAoAAf//AAAAAg7YAAAACgAB//8AAAACB9AAAAAKAAH//wAAAAIEsAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgZAAAAACgAB//8AAAACB9AAAAAKAAH//wAAAAIImAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgcIAAAACgAB//8AAAACDBwAAAAKAAH//wAAAAIQBAAAAAoAAf//AAAAAg7YAAAACAAAAAAAAAACAAAACgAB//8AAAACC1QAAAAKAAH//wAAAAIR+AAAAAoAAf//AAAAAgZAAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACASwAAAAKAAH//wAAAAILVAAAAAoAAf//AAAAAgakAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACCWAAAAAKAAH//wAAAAIHCAAAAAoAAf//AAAAAgEsAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAyAAAAAoAAf//AAAAAgDIAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACASwAAAAKAAH//wAAAAIDhAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgK8AAAACgAB//8AAAACCPwAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIBLAAAAAoAAf//AAAAAgGQAAAACgAB//8AAAACASwAAAAKAAH//wAAAAIbvAAAAAoAAf//AAAAAgXcAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACBXgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgDIAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgGQAAAACgAB//8AAAACASwAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACC7gAAAAKAAH//wAAAAIGpAAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAAC	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAOOAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAZAAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAyAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIBLAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgDIAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIBLAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACBEwAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAwAAgAAAAAAAgAJG1gAAAAKAAH//wAAAAIAyAAAAAoAAf//AAAAAgDIAAAADAACAAAAAAACAAIeeAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgGQAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAIAyAAAAAoAAf//AAAAAgUUAAAACgAB//8AAAACASwAAAAKAAH//wAAAAIFeAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACCJgAAAAMAAIAAAAAAAIABRosAAAADAACAAAAAAACAAEdTAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgSwAAAACgAB//8AAAACAMgAAAAKAAH//wAAAAIMHAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAhnIAAAADAACAAAAAAACAAMUUAAAAAwAAgAAAAAAAgABC7gAAAAKAAH//wAAAAIGpAAAAAoAAf//AAAAAgDIAAAACgAB//8AAAACEfgAAAAKAAH//wAAAAICWAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACDzwAAAAKAAH//wAAAAIBkAAAAAoAAf//AAAAAg4QAAAACAAAAAAAAAACAAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIAyAAAAAoAAf//AAAAAgnEAAAACgAB//8AAAACC7gAAAAKAAH//wAAAAIHbAAAAAoAAf//AAAAAgakAAAACgAB//8AAAACGvQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIGpAAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACgAB//8AAAACArwAAAAKAAH//wAAAAIMgAAAAAoAAf//AAAAAgGQAAAACgAB//8AAAACC7gAAAAKAAH//wAAAAIINAAAAAoAAf//AAAAAgDIAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAIBLAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgDIAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIFFAAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACAZAAAAAKAAH//wAAAAIAZAAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACgAB//8AAAACASwAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAoAAf//AAAAAgJYAAAACgAB//8AAAACAMgAAAAKAAH//wAAAAIDIAAAAAoAAf//AAAAAgOEAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACDBwAAAAKAAH//wAAAAIWqAAAAAwAAgAAAAAAAgAFDawAAAAMAAIAAAAAAAIAAhzoAAAADAACAAAAAAACAAIHCAAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAIHCAAAAAoAAf//AAAAAgDIAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAIOEAAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACCPwAAAAKAAH//wAAAAIZZAAAAAoAAf//AAAAAgOEAAAACgAB//8AAAACBkAAAAAKAAH//wAAAAIAZAAAAAoAAf//AAAAAgooAAAACgAB//8AAAACFXwAAAAKAAH//wAAAAIPoAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgtUAAAACgAB//8AAAACEGgAAAAKAAH//wAAAAIakAAAAAoAAf//AAAAAg88AAAACgAB//8AAAACBEwAAAAMAAIAAAAAAAIAAhqQAAAADAACAAAAAAACAAEbvAAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAADAACAAAAAAACAAIOEAAAAAwAAgAAAAAAAgACDBwAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACgAB//8AAAACAMgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIGpAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAMAAIAAAAAAAIACCPwAAAADAACAAAAAAACAAUkuAAAAAoAAf//AAAAAglgAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAMAAIAAAAAAAIAAQnEAAAACgAB//8AAAACASwAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIeeAAAAAoAAf//AAAAAgBkAAAACgAB//8AAAACIygAAAAKAAH//wAAAAIYnAAAAAoAAf//AAAAAgRMAAAACAAAAAAAAAACAAAADAACAAAAAAACAAER+AAAAAoAAf//AAAAAgRMAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAZAAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAoAAf//AAAAAgEsAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAoAAf//AAAAAiJgAAAADAACAAAAAAACAAEZZAAAAAoAAf//AAAAAgrwAAAACgAB//8AAAACImAAAAAKAAH//wAAAAIUtAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACBXgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAhJcAAAACgAB//8AAAACASwAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgDIAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgRMAAAACgAB//8AAAACASwAAAAKAAH//wAAAAIFFAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAwAAgAAAAAAAgAJEAQAAAAMAAIAAAAAAAIABSWAAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAI=	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAOOAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgABAAAAAAACAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIAAQAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAgAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIAAgAAAAoAAQAAAAAAAgAFAAAACgABAAAAAAACAAYAAAAKAAEAAAAAAAIAAgAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAgAAAAoAAQAAAAAAAgACAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACAAAAAAAAAACAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgACAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIAAgAAAAoAAQAAAAAAAgACAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIAEgAAAAoAAQAAAAAAAgARAAAACgABAAAAAAACABIAAAAKAAEAAAAAAAIABwAAAAoAAQAAAAAAAgAFAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAMAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgACAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIAAgAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIAAgAAAAoAAQAAAAAAAgABAAAACAAAAAAAAAACAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgABAAAAAAACAAEAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIAAQAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIAAQAAAAgAAAAAAAAAAgAAAAoAAQAAAAAAAgABAAAACAAAAAAAAAACAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIABgAAAAoAAQAAAAAAAgAGAAAACgABAAAAAAACAAUAAAAKAAEAAAAAAAIABgAAAAoAAQAAAAAAAgAHAAAACgABAAAAAAACAAYAAAAKAAEAAAAAAAIABQAAAAoAAQAAAAAAAgAFAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIABAAAAAoAAQAAAAAAAgAEAAAACgABAAAAAAACAAcAAAAKAAEAAAAAAAIAAwAAAAoAAQAAAAAAAgAFAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACAAAAAAAAAACAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACAAAAAAAAAACAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIAAgAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIABgAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAMAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIAYAAAAAoAAQAAAAAAAgBfAAAACgABAAAAAAACAGAAAAAKAAEAAAAAAAIAYAAAAAoAAQAAAAAAAgBfAAAACgABAAAAAAACAGAAAAAKAAEAAAAAAAIAXwAAAAoAAQAAAAAAAgBgAAAACgABAAAAAAACAF8AAAAKAAEAAAAAAAIAYAAAAAoAAQAAAAAAAgBgAAAACgABAAAAAAACAF8AAAAKAAEAAAAAAAIAXgAAAAoAAQAAAAAAAgBgAAAACgABAAAAAAACAGAAAAAKAAEAAAAAAAIAXwAAAAoAAQAAAAAAAgBgAAAACgABAAAAAAACAGAAAAAKAAEAAAAAAAIAYAAAAAoAAQAAAAAAAgBgAAAACgABAAAAAAACAGAAAAAKAAEAAAAAAAIAXwAAAAoAAQAAAAAAAgBfAAAACgABAAAAAAACAGAAAAAKAAEAAAAAAAIAYAAAAAoAAQAAAAAAAgBgAAAACgABAAAAAAACAF8AAAAKAAEAAAAAAAIAXwAAAAoAAQAAAAAAAgBfAAAACgABAAAAAAACAGAAAAAKAAEAAAAAAAIAYAAAAAoAAQAAAAAAAgBgAAAACgABAAAAAAACAF8AAAAKAAEAAAAAAAIAYAAAAAoAAQAAAAAAAgBfAAAACgABAAAAAAACAGAAAAAKAAEAAAAAAAIAXwAAAAoAAQAAAAAAAgBgAAAACgABAAAAAAACAF8AAAAKAAEAAAAAAAIAXwAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgALAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACwAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAsAAAAKAAEAAAAAAAIACwAAAAoAAQAAAAAAAgALAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAIAAAAKAAEAAAAAAAIAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAQAAAAAAAgACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgABAAAAAAACAAIAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgACAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgACAAAACAAAAAAAAAACAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIABgAAAAoAAQAAAAAAAgAVAAAACgABAAAAAAACABMAAAAKAAEAAAAAAAIAEgAAAAoAAQAAAAAAAgATAAAACgABAAAAAAACABMAAAAKAAEAAAAAAAIAEwAAAAoAAQAAAAAAAgASAAAACgABAAAAAAACABMAAAAKAAEAAAAAAAIAEwAAAAoAAQAAAAAAAgASAAAACgABAAAAAAACABMAAAAKAAEAAAAAAAIAEgAAAAoAAQAAAAAAAgASAAAACgABAAAAAAACABAAAAAKAAEAAAAAAAIAEQAAAAoAAQAAAAAAAgARAAAACgABAAAAAAACABEAAAAKAAEAAAAAAAIAEQAAAAoAAQAAAAAAAgAQAAAACgABAAAAAAACABAAAAAKAAEAAAAAAAIAEQAAAAoAAQAAAAAAAgAPAAAACgABAAAAAAACABAAAAAKAAEAAAAAAAIAEQAAAAoAAQAAAAAAAgAQAAAACgABAAAAAAACABAAAAAKAAEAAAAAAAIAEQAAAAoAAQAAAAAAAgARAAAACgABAAAAAAACABMAAAAKAAEAAAAAAAIAEQAAAAoAAQAAAAAAAgASAAAACgABAAAAAAACABQAAAAKAAEAAAAAAAIAEgAAAAoAAQAAAAAAAgAUAAAACgABAAAAAAACABMAAAAKAAEAAAAAAAIAFgAAAAoAAQAAAAAAAgAUAAAACgABAAAAAAACABMAAAAKAAEAAAAAAAIAFAAAAAoAAQAAAAAAAgAWAAAACgABAAAAAAACABIAAAAKAAEAAAAAAAIAFQAAAAoAAQAAAAAAAgAUAAAACgABAAAAAAACABQAAAAKAAEAAAAAAAIAFAAAAAoAAQAAAAAAAgAUAAAACgABAAAAAAACABQAAAAKAAEAAAAAAAIAFAAAAAoAAQAAAAAAAgAVAAAACgABAAAAAAACABUAAAAKAAEAAAAAAAIAFAAAAAoAAQAAAAAAAgAUAAAACgABAAAAAAACABQAAAAKAAEAAAAAAAIAFQAAAAoAAQAAAAAAAgAWAAAACgABAAAAAAACABUAAAAKAAEAAAAAAAIAEwAAAAoAAQAAAAAAAgAVAAAACgABAAAAAAACABUAAAAKAAEAAAAAAAIAFQAAAAoAAQAAAAAAAgAUAAAACgABAAAAAAACABMAAAAKAAEAAAAAAAIAFQAAAAoAAQAAAAAAAgAVAAAACgABAAAAAAACABQAAAAKAAEAAAAAAAIAEgAAAAoAAQAAAAAAAgAVAAAACgABAAAAAAACABQAAAAKAAEAAAAAAAIAFAAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAwAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgACAAAACgABAAAAAAACAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAQAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAgAAAAoAAQAAAAAAAgADAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAKAAEAAAAAAAIAAQAAAAoAAQAAAAAAAgABAAAACgABAAAAAAACAAEAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAEAAAAAAAIAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAQAAAAAAAgABAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAAC	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAOOAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAAC	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAAOOAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACEAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACEAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACEAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACIAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACMAAAAKAAEAAAAAAAIAIwAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACMAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAIwAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAIwAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAKAAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAnAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACcAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAnAAAACgABAAAAAAACACcAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACcAAAAKAAEAAAAAAAIAJwAAAAoAAQAAAAAAAgAoAAAACgABAAAAAAACACgAAAAKAAEAAAAAAAIAKAAAAAoAAQAAAAAAAgAoAAAACgABAAAAAAACACgAAAAKAAEAAAAAAAIAKQAAAAoAAQAAAAAAAgAqAAAACgABAAAAAAACACkAAAAKAAEAAAAAAAIAKwAAAAoAAQAAAAAAAgAqAAAACgABAAAAAAACACsAAAAKAAEAAAAAAAIALAAAAAoAAQAAAAAAAgAsAAAACgABAAAAAAACACwAAAAKAAEAAAAAAAIALgAAAAoAAQAAAAAAAgAuAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALwAAAAoAAQAAAAAAAgAxAAAACgABAAAAAAACADAAAAAKAAEAAAAAAAIAMgAAAAoAAQAAAAAAAgAzAAAACgABAAAAAAACADQAAAAKAAEAAAAAAAIANgAAAAoAAQAAAAAAAgA3AAAACgABAAAAAAACADsAAAAKAAEAAAAAAAIASwAAAAoAAQAAAAAAAgBLAAAACgABAAAAAAACAEsAAAAKAAEAAAAAAAIASwAAAAoAAQAAAAAAAgBLAAAACgABAAAAAAACAEsAAAAKAAEAAAAAAAIASwAAAAoAAQAAAAAAAgBLAAAACgABAAAAAAACAEsAAAAKAAEAAAAAAAIASwAAAAoAAQAAAAAAAgBLAAAACgABAAAAAAACAEoAAAAKAAEAAAAAAAIASwAAAAoAAQAAAAAAAgBLAAAACgABAAAAAAACAEsAAAAKAAEAAAAAAAIASwAAAAoAAQAAAAAAAgBKAAAACgABAAAAAAACAEsAAAAKAAEAAAAAAAIASgAAAAoAAQAAAAAAAgBKAAAACgABAAAAAAACAEoAAAAKAAEAAAAAAAIASgAAAAoAAQAAAAAAAgBKAAAACgABAAAAAAACAEoAAAAKAAEAAAAAAAIASgAAAAoAAQAAAAAAAgBKAAAACgABAAAAAAACAEoAAAAKAAEAAAAAAAIASQAAAAoAAQAAAAAAAgBJAAAACgABAAAAAAACAEkAAAAKAAEAAAAAAAIASAAAAAoAAQAAAAAAAgBIAAAACgABAAAAAAACAEcAAAAKAAEAAAAAAAIARwAAAAoAAQAAAAAAAgBHAAAACgABAAAAAAACAEcAAAAKAAEAAAAAAAIARQAAAAoAAQAAAAAAAgBFAAAACgABAAAAAAACAEQAAAAKAAEAAAAAAAIARAAAAAoAAQAAAAAAAgBAAAAACgABAAAAAAACAEAAAAAKAAEAAAAAAAIAPwAAAAoAAQAAAAAAAgA/AAAACgABAAAAAAACAD8AAAAKAAEAAAAAAAIAPgAAAAoAAQAAAAAAAgA9AAAACgABAAAAAAACADwAAAAKAAEAAAAAAAIAOwAAAAoAAQAAAAAAAgA5AAAACgABAAAAAAACADgAAAAKAAEAAAAAAAIANQAAAAoAAQAAAAAAAgAzAAAACgABAAAAAAACADAAAAAKAAEAAAAAAAIAIgAAAAoAAQAAAAAAAgAiAAAACgABAAAAAAACACIAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACMAAAAKAAEAAAAAAAIAIwAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAIwAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACMAAAAKAAEAAAAAAAIAIwAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACMAAAAKAAEAAAAAAAIAIwAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAnAAAACgABAAAAAAACACcAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJwAAAAoAAQAAAAAAAgAnAAAACgABAAAAAAACACcAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJwAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACcAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACcAAAAKAAEAAAAAAAIAJwAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACcAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJwAAAAoAAQAAAAAAAgAnAAAACgABAAAAAAACACcAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACMAAAAKAAEAAAAAAAIAIwAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACIAAAAKAAEAAAAAAAIAIgAAAAoAAQAAAAAAAgAiAAAACgABAAAAAAACACEAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACEAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAhAAAACgABAAAAAAACACIAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAiAAAACgABAAAAAAACACEAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAiAAAACgABAAAAAAACACEAAAAKAAEAAAAAAAIAIgAAAAoAAQAAAAAAAgAiAAAACgABAAAAAAACACIAAAAKAAEAAAAAAAIAIQAAAAoAAQAAAAAAAgAiAAAACgABAAAAAAACACMAAAAKAAEAAAAAAAIAIwAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACMAAAAKAAEAAAAAAAIAIwAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACMAAAAKAAEAAAAAAAIAIwAAAAoAAQAAAAAAAgAjAAAACgABAAAAAAACACMAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJAAAAAoAAQAAAAAAAgAkAAAACgABAAAAAAACACQAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACUAAAAKAAEAAAAAAAIAJgAAAAoAAQAAAAAAAgAlAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAJQAAAAoAAQAAAAAAAgAmAAAACgABAAAAAAACACYAAAAKAAEAAAAAAAIAKAAAAAoAAQAAAAAAAgAnAAAACgABAAAAAAACACgAAAAKAAEAAAAAAAIAKAAAAAoAAQAAAAAAAgAoAAAACgABAAAAAAACACgAAAAKAAEAAAAAAAIAKQAAAAoAAQAAAAAAAgAqAAAACgABAAAAAAACACoAAAAKAAEAAAAAAAIAKwAAAAoAAQAAAAAAAgArAAAACgABAAAAAAACACsAAAAKAAEAAAAAAAIALAAAAAoAAQAAAAAAAgAtAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIALgAAAAoAAQAAAAAAAgAvAAAACgABAAAAAAACADEAAAAKAAEAAAAAAAIAMQAAAAoAAQAAAAAAAgAzAAAACgABAAAAAAACADcAAAAKAAEAAAAAAAIAQwAAAAoAAQAAAAAAAgBDAAAACgABAAAAAAACAEMAAAAKAAEAAAAAAAIAQwAAAAoAAQAAAAAAAgBCAAAACgABAAAAAAACAEIAAAAKAAEAAAAAAAIAQwAAAAoAAQAAAAAAAgBDAAAACgABAAAAAAACAEMAAAAKAAEAAAAAAAIAQwAAAAoAAQAAAAAAAgBCAAAACgABAAAAAAACAEMAAAAKAAEAAAAAAAIAQgAAAAoAAQAAAAAAAgBDAAAACgABAAAAAAACAEIAAAAKAAEAAAAAAAIAQgAAAAoAAQAAAAAAAgBCAAAACgABAAAAAAACAEMAAAAKAAEAAAAAAAIAQgAAAAoAAQAAAAAAAgBCAAAACgABAAAAAAACAEIAAAAKAAEAAAAAAAIAQgAAAAoAAQAAAAAAAgBCAAAACgABAAAAAAACAEIAAAAKAAEAAAAAAAIAQgAAAAoAAQAAAAAAAgBCAAAACgABAAAAAAACAEIAAAAKAAEAAAAAAAIAQgAAAAoAAQAAAAAAAgBCAAAACgABAAAAAAACAEIAAAAKAAEAAAAAAAIAQgAAAAoAAQAAAAAAAgBCAAAACgABAAAAAAACAEIAAAAKAAEAAAAAAAIAQgAAAAoAAQAAAAAAAgBCAAAACgABAAAAAAACAEEAAAAKAAEAAAAAAAIAQgAAAAoAAQAAAAAAAgBCAAAACgABAAAAAAACAEEAAAAKAAEAAAAAAAIAQQAAAAoAAQAAAAAAAgBBAAAACgABAAAAAAACAEAAAAAKAAEAAAAAAAIAQAAAAAoAAQAAAAAAAgBAAAAACgABAAAAAAACAD8AAAAKAAEAAAAAAAIAPwAAAAoAAQAAAAAAAgA+AAAACgABAAAAAAACAD4AAAAKAAEAAAAAAAIAPQAAAAoAAQAAAAAAAgA8AAAACgABAAAAAAACADsAAAAKAAEAAAAAAAIAOgAAAAoAAQAAAAAAAgA4AAAACgABAAAAAAACADcAAAAKAAEAAAAAAAIANAAAAAoAAQAAAAAAAgAyAAAACgABAAAAAAACAC4AAAAKAAEAAAAAAAIAKAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAgAAAACgABAAAAAAACACAAAAAKAAEAAAAAAAIAIAAAAAoAAQAAAAAAAgAfAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHwAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB8AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB4AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAeAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHQAAAAoAAQAAAAAAAgAcAAAACgABAAAAAAACAB0AAAAKAAEAAAAAAAIAHgAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACABwAAAAKAAEAAAAAAAIAHAAAAAoAAQAAAAAAAgAcAAAACgABAAAAAAACABwAAAAKAAEAAAAAAAIAHAAAAAoAAQAAAAAAAgAcAAAACgABAAAAAAACABwAAAAKAAEAAAAAAAIAHAAAAAoAAQAAAAAAAgAdAAAACgABAAAAAAACABwAAAAKAAEAAAAAAAIAHAAAAAoAAQAAAAAAAgAcAAAACgABAAAAAAACABwAAAAKAAEAAAAAAAIAHAAAAAoAAQAAAAAAAgAcAAAACgABAAAAAAACABwAAAAKAAEAAAAAAAIAHAAAAAoAAQAAAAAAAgAcAAAACgABAAAAAAACABw=	BAAAAAAAAAACjv/////////yAAADjgAAADxEVFRVpURVS0NERDREVWRVVEQ0RENERDQAACIzdFRTRQACAAFgW2BIEhAgASEhStABACQYgAAEQAAAIgBEAMGhAAEgEgEAISAAABIBISAesACIIgAAEQAiAAIACs6tUAgABEAIgBEAAQEAIgBFLKAiEgASASABIAEAiAEQAihEQCABIBIBIBIAAIgBEAAbbQEgASASABIBIAEgEgASAS7RAAgBEAIgACIAiAEQAiBB4SECAQIBIBIAAAEIAEIB6UYABEAIgBEAIgAEQABEANuqIAEgASAAEgACASABIAECzUPLIAABACAQIFAoAOAoAAggEgEgEgzSAdEgEEMAAhIBASASABIAAS4gHtIAEgEgEgKBQKBQKAKBEhIAEgEgqyDJASASASABIAKBQKBQKAKBEgEgEgqyASABIBIBIBIBIBIBIBIBIAhwCpASASASASAUCgUAUUAUCgEgEgEghwEgABIBIBIBIBIBIBIBIBIByQHJASASASASAoAFAoFAoFABIAEhIB6xIJASASASASASQBIBIBIBIBwIhEAAAhIAIQAAAAiAEQA0ywEgASAAABIACgCgAUUUCgAAIgSiAAQCIAECAAABIAAABEEQIPCIARIAEgNAEgEgAAAGpjEAgIIAACk4QUiACgAKAAKBQAMaJAYGBhgAAAAAAAAAAAAIAA==	BAAAAAAAAAAAAgAAAAAAAAAAAAADjgAAAAQAAAAAAADy8wAAAAAAAAAcAAAMUAAAAAAAAAAAAAACRgAAKUAAAAAA	Bg==	Bg==	Bg==	Bg==	Bg==	Bg==
846	3	BAAAAAAAAAACb//////////+AAADTgAAACYzIzMzIzIzOzMzMzMzMzMzAAAAAAAzIiMAAAAAEhUSEgBhAAAAAAAAEAAAwgAAAAAAYQAADCAADAAAAAAAAAAAAAwgwgAAAAAAAAADCAAAAAAAAAAAAAAAAAAAAAAAGOEAAYQAAAAAYRhAAAMIAAAAAwgpEAAAAAAAiDCAAAYQAAAAAAAAAAAAJoAAAAAAAAAAAAAAAAY4SiJQCIAKTQRAIJpOEpOEFJoQCk44QY4Sk0IBhKRAABjSJwgAAwgAAAEAAAAYQAAAUCccIAAAAAAAAwgGEAAAAFAiAAAAADCAAAMIAABhAMcaGEoBEAAwgAAAAAAYQDCAYUcIMIKRAAAAQmOOEAwgGEEAAAADCYQAAThKThAMcIMIEGEAAAxoIlIAAAAAAAJGAgAAAAAAAAAAAAGAAAAAAAAAAAAAAAAAAAMIMcJhAAAA	2026-01-20 11:44:13.149931+05:30	2026-01-20 14:42:51.617864+05:30	BAAAAuvKfDRg6///////Hz+sAAADTgAAAWrczN3c3d3d7t3dzd3d3b3d3MzM3d3NzN3My93d28zd3d3Mzd283dy8vdzd3N3Mvd3d3N3d3d3c3czM3MzMzd3dy73d3dzdzMzd3d3d3N3d3d3d3d3d3d3d3dzN3d3d3d3M3dzd3c3d3M3d3bvd3d3c3czd3d3cvN3d3d3d3dzd3N3d3d3dzN3Mzd3d3d3d3d3d3d3d3d3d3MzMzN3d3d3NzL3czMzMzdzdzMzMzd3MzAAAAN3d3dzNAAXXmfYmcJAABdeZ91j3/QAltjAAIQQBAODBkwAEE4cAAcuqAMQUogAgmLQAAsJDACIAugAg+W0AA6hKACJO5RaAX/C5wrONACP5fAAaqmkApdNvACjrZQDWJDEBgJdKCSU8PrHCVdoliSCHOaMJImHi0AWAID1MAM6GJQAl85EAA0PMANcG5AFasW4Aq6aNAABfwgCtRz0vjJLrZfFLEAC1w08ABoIXAJY/IwFpr4QAAaAeAASHAwFvep4A1kuTANh1KwCVsEsAlIk1AW4g0gAFJhgAJXahEnKoZd3BW4EAKFpQAMxZywC2AO0BUmCuACCGdwAeYTQAILZRACED2gAeHeAABYe6AAWtGAAnlUkWpEyjgYGC9ASDHHUJBD34ACNCiwAYI3wK2RwVtEWl6gAg/rEAHsg0AAN/QQAHRJKlVZknAHfCUgAGBZKk3pLKBTokAlMAPYAB7bxRngESEQbN6Dph4TQcBFkcHmngibcAqYgLv2KX8gGX0KMAePOqAK/pzQEeXlYArJOLAV0dJACtfFEAAJRlALnSqQFm3UAEX8yBbaDxDRMRsBoZ4jywXykM1gmPav8AARFcAAG4JwFbugoArMwfAABHbACtF98AAHndAACqrwDtENgA7WHBDLEquxxX5noCKPQNEkA0WAZdFCl8gT/dAMTIAmhhVdoCDLwtLEBbJ6LCQbNXd8ApAWOcAdTgdOsAAGlvAAEfjAGxDD0AeoV4AACdlAE2Ue4eYgDcMaDuRUKkIFdYD86oAKyvrACs6+sArau2AAA4HwAAB38ArZn1AqsUCoGgJWACAhgibSGjTgEDDB5pQRCxAAEmMQAAPR4A3ra+AN2TcwAAjM8AADCOAVzxTgCu/IUAAHVQAK4gHyELOe58YxOSBEVMKPjAFW0OYmCGcSD99AFa0jAArWitAABROQCtpSsAZ7gheaD6CAAdVywAADvCAOe9cQApwaEAAxjIAO/UxAIYdAvRQThMAVvMcgCt98kAAIr/AK0z+Xh5UBbZsF4RAK04cQAAAVEArUljAVqyoHTh0CjVQRarAAf72AApL78AC02RACDhpAGSCvIA2BBXAkHsWwBdFWcAa0KrAa3bZgCNRkYAkhoIAACrVQCN9TkBHE3IAI2gvwACRwQAj/aNAS70HL7AUTkAkzftAAGw9wCOZBMBIk9OAI24uQAAKMAAAtXUARvoMgE5TMoByrIBAR5mEgCPxbMAAYj+AI9wdQCQdpQAlDlvA840IODA9jUIirwuY0DUuAZorB31AEsSDA78EXHBYQgFI/gV3cDcIgXvyDsVoACoAKNNLgCnQ70cRBrcsMLpewFtgDr79mgXAF+cEjYAzqAAASgF/WEHOS9cx0o2Qqi5Df2rCuronZYWt6QP11eV2A15/CbrsW8jAAA5sAADglYAzev2ALZ9X1xXMuktpcB3AIcJ4gAGaU8AkLr+ASaJowCUwIEAlhT2ASS1WgCP6zMBO+IQAR1jKwALIvIAuBnZMJ/SlTpsIOZgBBsYym/49gSK1BaJAAHbAL6OlwAAmMwAAHahAL7mngCTX9IAki+dAI2zDAAAfQUAjdRKARw9BwCOTPcAjmhwB6fELsGAmC8Aj3JOAI6L+QAPKFgAAEtgAJ+k8QCdhbIAhM7cAJqoEQE8HmMAtYIwAJEZVACMf7YABuHcAJUVjQH+dnYBcE5XAIYOXAEc4M0AkD/ZAJbqQgEgo84AkHRHAJE1PAEhKwMBHFuVAI/yzgAB2HkAjiQGARz9vQCQGsgAjoPcAI5wdACNzfkAjrMTARv8RwEchMQAjxdVARv51ACRQqEAAJDEAdU67QEfx6YBJj7lAd0jnACPXvIAjvrKAABnagCPP4MAj9XdAAApFwCOtqoAkB+cAR7HIgEe0E8AAZLxAI20EwCMmbUAABjxAI9aUwEcAToAi+M6AIzK0QCN2GsAkEVOARs0QgCNXb0AAO5uAI5g9wFApUMABUYTAKS67wHpQ+oYRkQOhcA7JgD+sASQ5Z1mAAVXhwAAHDoBG+w6AIg4+QAlW7cAdLx3AvAU5zvEPhAAi0P1AAGaQwEeFYMBHEMgAAFigQCQND4Ajor9AI9HGBRauJS14KfjAJwu7gCcQ8MAAiP9AAG8SAEizToAk5gXAAHguwCOFREEIPQQpGJbpgAAX2wAADbdAR0BigCN/skAAEGYAI6gewGUpAmo4BFKBhz0AtNBF7AAtCwO+aFgEAAA818AAIB0AKExWgChCIUBHZ2wAI60LwEb1IYBG+KlAJAHcAEdpK0Aj+MiAAI3hQAAjMcAjd3PWseJfHfmZFdQqliSjYFboQEcWC4AjfJ7AAAW6QCO/UUAj6A7AAGTSgCQFbcBHSaqAJ/HqgCeJ3sHenBgCkSIGwCOD80AAEYhAI7DvwEcafIBgnA4MGGJIoabTw4f2Ad0BRo8BMbhTLAAi9wXAACsVwCOTSoAjQm6AR34BAEd+k0BHGbAARxebQCxfKkAjgzXAJDjxQCxfOQAj6W3AR7pFgEfyDWj4Y42ARmwF2BAedYBHLWGAI6tdQAAbF8AjgOZBHyMRDdAybEAAEtwAAAQVwEeEg4AkBhXAADYVgCPXtMIvsghjyAwaAFjNwYBR5snAADeRQAca6kAjnX9AI7e7AEbeSAAjPuPAI2s9QCNtaUAjzafARtgugAAFuwAAHFkARvF6gCNHU0AABd9AI6L7wCMdykAAGEIAI5QOwEawu4CqxgT6WBLAgPijDqxAmAVAKD9uQAAxDYAARb0AKCkMgBIhCw6giedAYO8ScZA2+sAjgR0AI+fxQCN4iEAj1isAI0NcQAAkfsAjtbBARt9GACOIpsAANQIAR1JEQEcJv4Ajy53AR1JjgCOOY0AAM5cAI7W1wEcnnQAoZxNAABVWQEcm2YAFCQ+AADWqACOop8AjpYLAAB78QEdBRUBHOF4AR59zQEdB1IAjnOZAR6BjgEdGGwAjrhnAALCyQCNOPcAASY6AAEM3AEg6FYAkx3ZASgp1AEoJAUAhKkXAJhGCQCOdTcBHPZCALLCUwAAaE0AAEsZALOSAAjOuE1GYRiWBAAkCvpAsfEBH+kSAJEatwAAAGcAjhyPAR2AFACPXK0BHC54ARw5JQABI9EAjPylAI5ZlQAAnrcBHAu7AR0d9AAB1bwAjIJyARtw1QCNtu4AzTJgACnsywCPmUoAF3YrAIv/eQCOxtkAAWhBAIyU8AEb9LUAj5S0AI2QOgCOeGYAASDBAI3EfwEyJA4vwB2tAKYLkwAfV/4AuRqlATQQBACiMacAKAjCAAUWcgCBhmoAAldMAAFC3wCOOHsAjQC8AIxJKgEZK/sAAJKhAI5phg0lwEDqIbU5BiHswrChyz8iwYA5bWNLEAdhkGvcZXnvH3wgMUoDSPEOUMQJi+AeLgDtTBrSgPihALgfzwABhckAA7D3ALyxLAyyeGr4YblZZXdbdsB5KqpwM7/EBlqLkw31dAceItPeADHSjq14jjwID0gHqgELiwNGRE8BAko3ZMJ+8veAAKUAtvE7AAHLXgBjHsoAUzVisfESKjQbGXcSAViLniA4rhKrNBJCIJgAAKKQG9aDhLoAUaQEAcChUALOztSQd+iOBQjAWnLB6YUAAUsZAAMQmgGKWOcAjjiCAACBCQD7nBwERMARyqAG/Qgw1BaXwKXLBVWIGALAhzwAABQkwSA7+2+fzcqBP71ABJ7oHDFn7KYGZQRDbIGaBAAoSA0AHaRSAG8gtAAjQ/AE3XhqBd2KpRKhODYohnJdBUxY83LkJxcAm6FRAAJtqQCY+NMBNpceAS33yACU+ecBL/VEATACTQABM5cAl6oRASzHxACT6CMAAAAAAJAu7w==	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAANOAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACC7gAAAAKAAH//wAAAAIF3AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgnEAAAACAAAAAAAAAACAAAACgAB//8AAAACA+gAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgfQAAAACAAAAAAAAAACAAAACgAB//8AAAACA+gAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIVfAAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACDawAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACA+gAAAAKAAH//wAAAAIF3AAAAAoAAf//AAAAAg+gAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAhGUAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgnEAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAINrAAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACITQAAAAKAAH//wAAAAINrAAAAAoAAf//AAAAAgXcAAAACAAAAAAAAAACAAAACgAB//8AAAACCcQAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgXcAAAACgAB//8AAAACA+gAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACC7gAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgnEAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACGWQAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACDawAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACBdwAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgPoAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACEZQAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACA+gAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgu4AAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgfQAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAhOIAAAACAAAAAAAAAACAAAACgAB//8AAAACE4gAAAAKAAH//wAAAAIF3AAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACA+gAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAg+gAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgXcAAAACgAB//8AAAACA+gAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgnEAAAACgAB//8AAAACC7gAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIH0AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgPoAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgfQAAAACAAAAAAAAAACAAAACgAB//8AAAACA+gAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgPoAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACC7gAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIF3AAAAAoAAf//AAAAAgu4AAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAhOIAAAACgAB//8AAAACEZQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACDawAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACA+gAAAAKAAH//wAAAAINrAAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgPoAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIF3AAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACB9AAAAAKAAH//wAAAAIPoAAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIJxAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACB9AAAAAKAAH//wAAAAINrAAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACBdwAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAILuAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgPoAAAACAAAAAAAAAACAAAACgAB//8AAAACB9AAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIF3AAAAAoAAf//AAAAAg2sAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACA+gAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgfQAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACDawAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgXcAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAILuAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgXcAAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIJxAAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACC7gAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgu4AAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIF3AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACA+gAAAAKAAH//wAAAAILuAAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAILuAAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACA+gAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACBdwAAAAKAAH//wAAAAITiAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACC7gAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAhGUAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACEZQAAAAKAAH//wAAAAIPoAAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACA+gAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAhV8AAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgfQAAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIF3AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIF3AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACD6AAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACB9AAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgnEAAAACgAB//8AAAACA+gAAAAKAAH//wAAAAIF3AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgnEAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACA+gAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIH0AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACA+gAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACCcQAAAAKAAH//wAAAAIF3AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAg2sAAAACgAB//8AAAACBdwAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACB9AAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACA+gAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAg+gAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACBdwAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgPoAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAILuAAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACA+gAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIF3AAAAAoAAf//AAAAAg2sAAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACA+gAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgfQAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACA+gAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAITiAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgPoAAAACAAAAAAAAAACAAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIH0AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACA+gAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgPoAAAACAAAAAAAAAACAAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIH0AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAKAAH//wAAAAINrAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgfQAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACD6AAAAAKAAH//wAAAAIF3AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACB9AAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAKAAH//wAAAAILuAAAAAoAAf//AAAAAhlkAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgfQAAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIF3AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACA+gAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACBdwAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIH0AAAAAoAAf//AAAAAhGUAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACA+gAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACC7gAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgH0AAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAINrAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgXcAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAMAAIAAAAAAAIAAQ+gAAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAID6AAAAAoAAf//AAAAAgPoAAAACgAB//8AAAACB9AAAAAKAAH//wAAAAIH0AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACCcQAAAAKAAH//wAAAAID6AAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgXcAAAACAAAAAAAAAACAAAACgAB//8AAAACFXwAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACAfQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAg+gAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgXcAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACA+gAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgPoAAAACAAAAAAAAAACAAAACgAB//8AAAACAfQAAAAKAAH//wAAAAIB9AAAAAoAAf//AAAAAgH0AAAACgAB//8AAAACBdwAAAAIAAAAAAAAAAIAAAAMAAIAAAAAAAIAAQnEAAAACgAB//8AAAACB9AAAAAKAAH//wAAAAIF3AAAAAoAAf//AAAAAgH0AAAACgAB//8A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AAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9AAAAADAACAAAAAAACABsfQAAAAAwAAgAAAAAAAgAbH0AAAAAMAAIAAAAAAAIAGx9A	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAANOAAAADAACAAAAAAACABEI/AAAAAwAAgAAAAAAAgARCDQAAAAMAAIAAAAAAAIAEQg0AAAADAACAAAAAAACABEImAAAAAwAAgAAAAAAAgARCJgAAAAMAAIAAAAAAAIAEQj8AAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARCPwAAAAMAAIAAAAAAAIAEQiYAAAADAACAAAAAAACABEINAAAAAwAAgAAAAAAAgARCPwAAAAMAAIAAAAAAAIAEQlgAAAADAACAAAAAAACABEJxAAAAAwAAgAAAAAAAgARCigAAAAMAAIAAAAAAAIAEQooAAAADAACAAAAAAACABEJYAAAAAwAAgAAAAAAAgARCcQAAAAMAAIAAAAAAAIAEQlgAAAADAACAAAAAAACABEI/AAAAAwAAgAAAAAAAgARCWAAAAAMAAIAAAAAAAIAEQooAAAADAACAAAAAAACABEI/AAAAAwAAgAAAAAAAgARCPwAAAAMAAIAAAAAAAIAEQg0AAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB9AAAAAMAAIAAAAAAAIAEQfQAAAADAACAAAAAAACABEImAAAAAwAAgAAAAAAAgARCPwAAAAMAAIAAAAAAAIAEQlgAAAADAACAAAAAAACABEINAAAAAwAAgAAAAAAAgARCDQAAAAMAAIAAAAAAAIAEQfQAAAADAACAAAAAAACABEI/AAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQfQAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARCPwAAAAMAAIAAAAAAAIAEQiYAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARB9AAAAAMAAIAAAAAAAIAEQg0AAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARCDQAAAAMAAIAAAAAAAIAEQdsAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARCJgAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQdsAAAADAACAAAAAAACABEHCAAAAAwAAgAAAAAAAgARB9AAAAAMAAIAAAAAAAIAEQg0AAAADAACAAAAAAACABEI/AAAAAwAAgAAAAAAAgARCWAAAAAMAAIAAAAAAAIAEQnEAAAADAACAAAAAAACABEJxAAAAAwAAgAAAAAAAgARCPwAAAAMAAIAAAAAAAIAEQnEAAAADAACAAAAAAACABEI/AAAAAwAAgAAAAAAAgARCPwAAAAMAAIAAAAAAAIAEQfQAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARCPwAAAAMAAIAAAAAAAIAEQj8AAAADAACAAAAAAACABEJYAAAAAwAAgAAAAAAAgARCWAAAAAMAAIAAAAAAAIAEQj8AAAADAACAAAAAAACABEJYAAAAAwAAgAAAAAAAgARCWAAAAAMAAIAAAAAAAIAEQj8AAAADAACAAAAAAACABEI/AAAAAwAAgAAAAAAAgARCcQAAAAMAAIAAAAAAAIAEQlgAAAADAACAAAAAAACABEKKAAAAAwAAgAAAAAAAgARCcQAAAAMAAIAAAAAAAIAEQlgAAAADAACAAAAAAACABEKKAAAAAwAAgAAAAAAAgARCigAAAAMAAIAAAAAAAIAEQj8AAAADAACAAAAAAACABEI/AAAAAwAAgAAAAAAAgARCJgAAAAMAAIAAAAAAAIAEQj8AAAADAACAAAAAAACABEI/AAAAAwAAgAAAAAAAgARCPwAAAAMAAIAAAAAAAIAEQqMAAAADAACAAAAAAACABEKjAAAAAwAAgAAAAAAAgARC1QAAAAMAAIAAAAAAAIAEQfQAAAADAACAAAAAAACABEINAAAAAwAAgAAAAAAAgARCDQAAAAMAAIAAAAAAAIAEQg0AAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB9AAAAAMAAIAAAAAAAIAEQj8AAAADAACAAAAAAACABEImAAAAAwAAgAAAAAAAgARCJgAAAAMAAIAAAAAAAIAEQg0AAAADAACAAAAAAACABEINAAAAAwAAgAAAAAAAgARB9AAAAAMAAIAAAAAAAIAEQg0AAAADAACAAAAAAACABEINAAAAAwAAgAAAAAAAgARB9AAAAAMAAIAAAAAAAIAEQdsAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB9AAAAAMAAIAAAAAAAIAEQiYAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQg0AAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEHCAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEGQAAAAAwAAgAAAAAAAgARB9AAAAAMAAIAAAAAAAIAEQfQAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQg0AAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB9AAAAAMAAIAAAAAAAIAEQg0AAAADAACAAAAAAACABEJYAAAAAwAAgAAAAAAAgARCcQAAAAMAAIAAAAAAAIAEQj8AAAADAACAAAAAAACABEI/AAAAAwAAgAAAAAAAgARCPwAAAAMAAIAAAAAAAIAEQlgAAAADAACAAAAAAACABEI/AAAAAwAAgAAAAAAAgARCDQAAAAMAAIAAAAAAAIAEQiYAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQg0AAAADAACAAAAAAACABEJxAAAAAwAAgAAAAAAAgARCWAAAAAMAAIAAAAAAAIAEQiYAAAADAACAAAAAAACABEINAAAAAwAAgAAAAAAAgARCDQAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEF3AAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQfQAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARB9AAAAAMAAIAAAAAAAIAEQg0AAAADAACAAAAAAACABEINAAAAAwAAgAAAAAAAgARCDQAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEGQAAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEGQAAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARBkAAAAAMAAIAAAAAAAIAEQXcAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARBkAAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB9AAAAAMAAIAAAAAAAIAEQdsAAAADAACAAAAAAACABEHCAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEHCAAAAAwAAgAAAAAAAgARBkAAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEF3AAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQdsAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARCDQAAAAMAAIAAAAAAAIAEQiYAAAADAACAAAAAAACABEINAAAAAwAAgAAAAAAAgARCDQAAAAMAAIAAAAAAAIAEQdsAAAADAACAAAAAAACABEHCAAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQdsAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARCDQAAAAMAAIAAAAAAAIAEQdsAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARB9AAAAAMAAIAAAAAAAIAEQiYAAAADAACAAAAAAACABEImAAAAAwAAgAAAAAAAgARCJgAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEHCAAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEF3AAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEGQAAAAAwAAgAAAAAAAgARBkAAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEHCAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQfQAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQfQAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQfQAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEHCAAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQUUAAAADAACAAAAAAACABEFFAAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEHCAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEGQAAAAAwAAgAAAAAAAgARBkAAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEHCAAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEFeAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQXcAAAADAACAAAAAAACABEF3AAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARCDQAAAAMAAIAAAAAAAIAEQdsAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEF3AAAAAwAAgAAAAAAAgARBkAAAAAMAAIAAAAAAAIAEQV4AAAADAACAAAAAAACABEFFAAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQV4AAAADAACAAAAAAACABEF3AAAAAwAAgAAAAAAAgARBXgAAAAMAAIAAAAAAAIAEQUUAAAADAACAAAAAAACABEEsAAAAAwAAgAAAAAAAgARBXgAAAAMAAIAAAAAAAIAEQXcAAAADAACAAAAAAACABEFFAAAAAwAAgAAAAAAAgARBXgAAAAMAAIAAAAAAAIAEQUUAAAADAACAAAAAAACABEEsAAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQV4AAAADAACAAAAAAACABEFeAAAAAwAAgAAAAAAAgARBRQAAAAMAAIAAAAAAAIAEQXcAAAADAACAAAAAAACABEFeAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQXcAAAADAACAAAAAAACABEFeAAAAAwAAgAAAAAAAgARBXgAAAAMAAIAAAAAAAIAEQV4AAAADAACAAAAAAACABEFFAAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQV4AAAADAACAAAAAAACABEEsAAAAAwAAgAAAAAAAgARBXgAAAAMAAIAAAAAAAIAEQXcAAAADAACAAAAAAACABEF3AAAAAwAAgAAAAAAAgARBRQAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEF3AAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQXcAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARBkAAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARB2wAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQXcAAAADAACAAAAAAACABEGQAAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQXcAAAADAACAAAAAAACABEF3AAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQXcAAAADAACAAAAAAACABEFeAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEGQAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEGQAAAAAwAAgAAAAAAAgARBkAAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEGQAAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQfQAAAADAACAAAAAAACABEHbAAAAAwAAgAAAAAAAgARBkAAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARBkAAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABEHCAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQV4AAAADAACAAAAAAACABEFeAAAAAwAAgAAAAAAAgARBXgAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEGQAAAAAwAAgAAAAAAAgARBXgAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEFeAAAAAwAAgAAAAAAAgARBXgAAAAMAAIAAAAAAAIAEQZAAAAADAACAAAAAAACABEFeAAAAAwAAgAAAAAAAgARBXgAAAAMAAIAAAAAAAIAEQRMAAAADAACAAAAAAACABEETAAAAAwAAgAAAAAAAgARBEwAAAAMAAIAAAAAAAIAEQSwAAAADAACAAAAAAACABEFFAAAAAwAAgAAAAAAAgARBdwAAAAMAAIAAAAAAAIAEQUUAAAADAACAAAAAAACABEETAAAAAwAAgAAAAAAAgARBEwAAAAMAAIAAAAAAAIAEQRMAAAADAACAAAAAAACABEETAAAAAwAAgAAAAAAAgARA+gAAAAMAAIAAAAAAAIAEQOEAAAADAACAAAAAAACABED6AAAAAwAAgAAAAAAAgARA+gAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARAlgAAAAMAAIAAAAAAAIAEQRMAAAADAACAAAAAAACABEETAAAAAwAAgAAAAAAAgARBqQAAAAMAAIAAAAAAAIAEQ4QAAAADAACAAAAAAACABED6AAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDhAAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDhAAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARAlgAAAAMAAIAAAAAAAIAEQJYAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARAlgAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARAlgAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDhAAAAAwAAgAAAAAAAgARA+gAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABEDhAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEB9AAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQJYAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARAlgAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQGQAAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARAlgAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABED6AAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQJYAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQPoAAAADAACAAAAAAACABEDhAAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQPoAAAADAACAAAAAAACABED6AAAAAwAAgAAAAAAAgARA+gAAAAMAAIAAAAAAAIAEQPoAAAADAACAAAAAAACABEEsAAAAAwAAgAAAAAAAgARA+gAAAAMAAIAAAAAAAIAEQSwAAAADAACAAAAAAACABEFFAAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDhAAAAAwAAgAAAAAAAgARA+gAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARAlgAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARA+gAAAAMAAIAAAAAAAIAEQOEAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQOEAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQOEAAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQUUAAAADAACAAAAAAACABEFFAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARAlgAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQJYAAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARASwAAAAMAAIAAAAAAAIAEQH0AAAADAACAAAAAAACABEB9AAAAAwAAgAAAAAAAgARASwAAAAMAAIAAAAAAAIAEQH0AAAADAACAAAAAAACABEB9AAAAAwAAgAAAAAAAgARAZAAAAAMAAIAAAAAAAIAEQDIAAAADAACAAAAAAACABEAZAAAAAwAAgAAAAAAAgARAZAAAAAMAAIAAAAAAAIAEQEsAAAADAACAAAAAAACABEBkAAAAAwAAgAAAAAAAgARAZAAAAAMAAIAAAAAAAIAEQGQAAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARAZAAAAAMAAIAAAAAAAIAEQH0AAAADAACAAAAAAACABEB9AAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQJYAAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQJYAAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARA+gAAAAMAAIAAAAAAAIAEQJYAAAADAACAAAAAAACABEBkAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDhAAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABEDhAAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQJYAAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARAfQAAAAMAAIAAAAAAAIAEQGQAAAADAACAAAAAAACABEBkAAAAAwAAgAAAAAAAgARAfQAAAAMAAIAAAAAAAIAEQH0AAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARAlgAAAAMAAIAAAAAAAIAEQGQAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARBEwAAAAMAAIAAAAAAAIAEQOEAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARBEwAAAAMAAIAAAAAAAIAEQOEAAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDhAAAAAwAAgAAAAAAAgARAlgAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABEDhAAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQJYAAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARAfQAAAAMAAIAAAAAAAIAEQPoAAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQOEAAAADAACAAAAAAACABEDhAAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQH0AAAADAACAAAAAAACABEB9AAAAAwAAgAAAAAAAgARAlgAAAAMAAIAAAAAAAIAEQOEAAAADAACAAAAAAACABED6AAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQRMAAAADAACAAAAAAACABED6AAAAAwAAgAAAAAAAgARA+gAAAAMAAIAAAAAAAIAEQOEAAAADAACAAAAAAACABED6AAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABEDhAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQOEAAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQH0AAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARBkAAAAAMAAIAAAAAAAIAEQakAAAADAACAAAAAAACABEGQAAAAAwAAgAAAAAAAgARBwgAAAAMAAIAAAAAAAIAEQfQAAAADAACAAAAAAACABEEsAAAAAwAAgAAAAAAAgARA+gAAAAMAAIAAAAAAAIAEQGQAAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARAfQAAAAMAAIAAAAAAAIAEQGQAAAADAACAAAAAAACABEB9AAAAAwAAgAAAAAAAgARAfQAAAAMAAIAAAAAAAIAEQOEAAAADAACAAAAAAACABEB9AAAAAwAAgAAAAAAAgARAZAAAAAMAAIAAAAAAAIAEQK8AAAADAACAAAAAAACABEAZAAAAAwAAgAAAAAAAgARAMgAAAAMAAIAAAAAAAIAEQDIAAAADAACAAAAAAACABEH0AAAAAwAAgAAAAAAAgARA4QAAAAMAAIAAAAAAAIAEQGQAAAADAACAAAAAAACABEBkAAAAAwAAgAAAAAAAgARAfQAAAAMAAIAAAAAAAIAEQEsAAAADAACAAAAAAACABEAZAAAAAwAAgAAAAAAAgARAMgAAAAMAAIAAAAAAAIAEQEsAAAACgABAAAAAAACABEAAAAMAAIAAAAAAAIAEQDIAAAADAACAAAAAAACABEBkAAAAAwAAgAAAAAAAgARASwAAAAMAAIAAAAAAAIAEQH0AAAADAACAAAAAAACABECWAAAAAwAAgAAAAAAAgARAlgAAAAMAAIAAAAAAAIAEQH0AAAADAACAAAAAAACABEB9AAAAAwAAgAAAAAAAgARAMgAAAAMAAIAAAAAAAIAEQH0AAAADAACAAAAAAACABEB9AAAAAwAAgAAAAAAAgARAfQAAAAMAAIAAAAAAAIAEQJYAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARDnQAAAAMAAIAAAAAAAIAEQV4AAAADAACAAAAAAACABEDIAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQOEAAAADAACAAAAAAACABED6AAAAAwAAgAAAAAAAgARAfQAAAAMAAIAAAAAAAIAEQGQAAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARAyAAAAAMAAIAAAAAAAIAEQJYAAAADAACAAAAAAACABECvAAAAAwAAgAAAAAAAgARArwAAAAMAAIAAAAAAAIAEQMgAAAADAACAAAAAAACABEFFAAAAAwAAgAAAAAAAgARBEwAAAAMAAIAAAAAAAIAEQSwAAAADAACAAAAAAACABEINAAAAAwAAgAAAAAAAgARCDQAAAAMAAIAAAAAAAIAEQ88AAAADAACAAAAAAACABESwAAAAAwAAgAAAAAAAgARElwAAAAMAAIAAAAAAAIAERJcAAAADAACAAAAAAACABESXAAAAAwAAgAAAAAAAgAREsAAAAAMAAIAAAAAAAIAERMkAAAADAACAAAAAAACABETJAAAAAwAAgAAAAAAAgAREyQAAAAMAAIAAAAAAAIAEROIAAAADAACAAAAAAACABESwAAAAAwAAgAAAAAAAgAREsAAAAAMAAIAAAAAAAIAERJcAAAADAACAAAAAAACABETJAAAAAwAAgAAAAAAAgAREfgAAAAMAAIAAAAAAAIAERJcAAAADAACAAAAAAACABERlAAAAAwAAgAAAAAAAgARElwAAAAMAAIAAAAAAAIAEROIAAAADAACAAAAAAACABETiAAAAAwAAgAAAAAAAgARE4gAAAAMAAIAAAAAAAIAERPsAAAADAACAAAAAAACABETiAAAAAwAAgAAAAAAAgAREfgAAAAMAAIAAAAAAAIAERH4AAAADAACAAAAAAACABERMAAAAAwAAgAAAAAAAgARETAAAAAMAAIAAAAAAAIAERGUAAAADAACAAAAAAACABEQzAAAAAwAAgAAAAAAAgAREZQAAAAMAAIAAAAAAAIAERLAAAAADAACAAAAAAACABERlAAAAAwAAgAAAAAAAgARETAAAAAMAAIAAAAAAAIAERDMAAAADAACAAAAAAACABEQzAAAAAwAAgAAAAAAAgAREZQAAAAMAAIAAAAAAAIAERGUAAAADAACAAAAAAACABESwAAAAAwAAgAAAAAAAgAREfgAAAAMAAIAAAAAAAIAERRQAAAADAACAAAAAAACABERlAAAAAwAAgAAAAAAAgARElwAAAAMAAIAAAAAAAIAERLAAAAADAACAAAAAAACABETiAAAAAwAAgAAAAAAAgARElwAAAAMAAIAAAAAAAIAERLAAAAADAACAAAAAAACABESXAAAAAwAAgAAAAAAAgARFRgAAAAMAAIAAAAAAAIAERDMAAAADAACAAAAAAACABET7AAAAAwAAgAAAAAAAgARETAAAAAMAAIAAAAAAAIAERGUAAAADAACAAAAAAACABETJAAAAAwAAgAAAAAAAgARElwAAAAMAAIAAAAAAAIAERH4AAAADAACAAAAAAACABESXAAAAAwAAgAAAAAAAgARElwAAAAMAAIAAAAAAAIAERLAAAAADAACAAAAAAACABER+AAAAAwAAgAAAAAAAgAREZQAAAAMAAIAAAAAAAIAERH4AAAADAACAAAAAAACABETJAAAAAwAAgAAAAAAAgARElwAAAAMAAIAAAAAAAIAERH4AAAADAACAAAAAAACABER+AAAAAwAAgAAAAAAAgAREfgAAAAMAAIAAAAAAAIAERJcAAAADAACAAAAAAACABER+AAAAAwAAgAAAAAAAgAREsAAAAAMAAIAAAAAAAIAERPsAAAADAACAAAAAAACABEUUAAAAAwAAgAAAAAAAgARFXwAAAAMAAIAAAAAAAIAERwgAAAADAACAAAAAAACABEGpAAAAAwAAgAAAAAAAgARBEwAAAAMAAIAAAAAAAIAEQRMAAAADAACAAAAAAACABED6AAAAAwAAgAAAAAAAgARBEwAAAAMAAIAAAAAAAIAEQSwAAAADAACAAAAAAACABED6AAAAAwAAgAAAAAAAgARA+gAAAAMAAIAAAAAAAIAEQRMAAAADAACAAAAAAACABEETAAAAAwAAgAAAAAAAgARBLAAAAAMAAIAAAAAAAIAEQSwAAAADAACAAAAAAACABEEsAAAAAwAAgAAAAAAAgARBXgAAAAMAAIAAAAAAAIAEQqMAAAADAACAAAAAAACABETJAAAAAwAAgAAAAAAAgARElwAAAAMAAIAAAAAAAIAERH4AAAADAACAAAAAAACABERMAAAAAwAAgAAAAAAAgAREfgAAAAMAAIAAAAAAAIAERH4AAAADAACAAAAAAACABERlAAAAAwAAgAAAAAAAgAREZQAAAAMAAIAAAAAAAIAERJcAAAADAACAAAAAAACABER+AAAAAwAAgAAAAAAAgAREfgAAAAMAAIAAAAAAAIAERH4AAAADAACAAAAAAACABERlAAAAAwAAgAAAAAAAgAREZQAAAAMAAIAAAAAAAIAEREwAAAADAACAAAAAAACABERlAAAAAwAAgAAAAAAAgAREsAAAAAMAAIAAAAAAAIAERGUAAAADAACAAAAAAACABER+AAAAAwAAgAAAAAAAgARETAAAAAMAAIAAAAAAAIAERDMAAAADAACAAAAAAACABEQzAAAAAwAAgAAAAAAAgAREMwAAAAMAAIAAAAAAAIAERBoAAAADAACAAAAAAACABEQBAAAAAwAAgAAAAAAAgAREGgAAAAMAAIAAAAAAAIAERBoAAAADAACAAAAAAACABEPoAAAAAwAAgAAAAAAAgARFwwAAAAMAAIAAAAAAAIAERtYAAAADAACAAAAAAACABEX1AAAAAwAAgAAAAAAAgARFwwAAAAMAAIAAAAAAAIAERtYAAAADAACAAAAAAACABEa9AAAAAwAAgAAAAAAAgARGpAAAAAMAAIAAAAAAAIAERMkAAAADAACAAAAAAACABEM5AAAAAwAAgAAAAAAAgARDOQAAAAMAAIAAAAAAAIAEQ2sAAAADAACAAAAAAACABEO2AAAAAwAAgAAAAAAAgAREMwAAAAMAAIAAAAAAAIAEQrwAAAADAACAAAAAAACABEMHAAAAAwAAgAAAAAAAgARC7gAAAAMAAIAAAAAAAIAEQcIAAAADAACAAAAAAACABELuAAAAAwAAgAAAAAAAgARH6QAAAAMAAIAAAAAAAIAEB54AAAADAACAAAAAAACABAeFAAAAAwAAgAAAAAAAgAQHngAAAAMAAIAAAAAAAIAEB7cAAAADAACAAAAAAACABAeeAAAAAwAAgAAAAAAAgAQHtwAAAAMAAIAAAAAAAIAEB4UAAAADAACAAAAAAACABAeFAAAAAwAAgAAAAAAAgAQHbAAAAAMAAIAAAAAAAIAEByEAAAADAACAAAAAAACABAeFAAAAAwAAgAAAAAAAgAQHbAAAAAMAAIAAAAAAAIAEB1MAAAADAACAAAAAAACABAeFAAAAAwAAgAAAAAAAgAQHhQAAAAMAAIAAAAAAAIAEB9AAAAADAACAAAAAAACABAeeAAAAAwAAgAAAAAAAgAQHUwAAAAMAAIAAAAAAAIAEBzoAAAADAACAAAAAAACABAchAAAAAwAAgAAAAAAAgAQHIQAAAAMAAIAAAAAAAIAEB1MAAAADAACAAAAAAACABAc6AAAAAwAAgAAAAAAAgAQHngAAAAMAAIAAAAAAAIAEB4UAAAADAACAAAAAAACABAeeAAAAAwAAgAAAAAAAgAQHUwAAAAMAAIAAAAAAAIAEB2wAAAADAACAAAAAAACABAeFAAAAAwAAgAAAAAAAgAQHbAAAAAMAAIAAAAAAAIAEB54AAAADAACAAAAAAACABAe3AAAAAwAAgAAAAAAAgAQH0AAAAAMAAIAAAAAAAIAEB+kAAAADAACAAAAAAACABAl5AAAAAwAAgAAAAAAAgAQHUwAAAAMAAIAAAAAAAIAEBzoAAAADAACAAAAAAACABAh/A==	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAANOAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAKAAAACgABAAAAAAACAAoAAAAKAAEAAAAAAAIACgAAAAoAAQAAAAAAAgAK	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAANOAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtAAAAAoAAf//AAAAAhS0AAAACgAB//8AAAACFLQAAAAKAAH//wAAAAIUtA==	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAANOAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAINrAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgDIAAAACgAB//8AAAACAZAAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgGQAAAACgAB//8AAAACAlgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAyAAAAAoAAf//AAAAAg+gAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIBLAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgDIAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAoAAf//AAAAAgGQAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIPPAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIOEAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAg88AAAACgAB//8AAAACASwAAAAIAAAAAAAAAAIAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABwOEAAAADAACAAAAAAACAAcDhAAAAAwAAgAAAAAAAgAHA4QAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0AAAAAwAAgAAAAAAAgAGINAAAAAMAAIAAAAAAAIABiDQAAAADAACAAAAAAACAAYg0A==	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAANOAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACB9AAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgEsAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAMgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIBkAAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAKAAH//wAAAAIAZAAAAAoAAf//AAAAAgJYAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAMgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAI=	AQBwZ19jYXRhbG9nAG51bWVyaWMAAAEAAANOAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAMgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAyAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgDIAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAMgAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgDIAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAyAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAADAACAAAAAAACAAkDIAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgBkAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgMgAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACAAAAAAAAAACAAAACgAB//8AAAACASwAAAAKAAH//wAAAAIAZAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgOEAAAACgAB//8AAAACA+gAAAAKAAH//wAAAAIKKAAAAAgAAAAAAAAAAgAAAAoAAf//AAAAAgEsAAAACAAAAAAAAAACAAAACgAB//8AAAACAGQAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAIAAAAAAAAAAIAAAAKAAH//wAAAAIXcAAAAAgAAAAAAAAAAgAAAAgAAAAAAAAAAg==	Bg==	Bg==	Bg==	BAAAAAAAAAAGZP/////////xAAADTgAAADpEVURVqkU0S0RFRDREVWVVRDRDREQ0REMAAAAnVUVURQACAAFglWCCEhAgASEgDNAO0SEgAAABAhQKBAQBQBQKAIgiAGDxAAAgEhIAASABIArVAIAAAAABAAIAAAEAKs4ABEAIgACIAQEAIgBEANuqEgASASABIAEBIBIBIAEg7QUAARACIARAAIgBEAARAp2wASASABIBIAEgASASASAMB4RBEAARACIAiAEQABEAMgAAQRACIARAAAEIAGCUYQMAiAAIgBEEQAAEQAiBT7AAAAEgABIAEgAAASAAEhLNAskBIAEAIBI0IFAoEIAAAhEgEgEgHrASAQAQISEAIBIBAARACIAAwaABIBIBIBIBIAEgEgASASzSCrIBIBIBIBIUCgUAQgCgCgEgASASqRIAIBIBIBIBIBIgEgEgEgEgqwHJASASASABAoFAoFAoFAoBIAEgEgqRIHASASASASASEgEgEgEgEgggCrIBIBIBICBQKBQKBQKBIBIBIBIByQGpASABIAEgARQKBQKBQKBQEgEgEgqyASASABAhAAIBIAAAARACIEHgABIAEgAAEgASAAEhISAB6wAAIgiAAARAAARAAAAAilHxIAEgEhIAAAEAARACIAAyAQRAAAAQkAECAAAFDCIBAQAAAAAYJGkB	BAAAAAAAAAAAAgAAAAAAAAAAAAADTgAAAAIAAAAAAAAA8wAAAAAAAAAcAAAzkAAAAAA=	Bg==	Bg==	Bg==	Bg==	Bg==	Bg==
\.


--
-- Data for Name: collection_credentials; Type: TABLE DATA; Schema: public; Owner: aayush
--

COPY public.collection_credentials (credential_id, credential_name, credential_type, username, password_encrypted, ssh_key_path, snmp_community, additional_config, is_active, created_at, last_used, used_count) FROM stdin;
\.


--
-- Data for Name: departments; Type: TABLE DATA; Schema: public; Owner: aayush
--

COPY public.departments (dept_id, dept_name, dept_code, vlan_id, subnet_cidr, description, hod_id) FROM stdin;
1	Information Science Engineering	ISE	100	192.168.0.0/24	Information Science Department	1
2	Computer Science Engineering	CSE	VLAN100	192.168.1.0/24	Computer Science Engineering Department	\N
\.


--
-- Data for Name: hods; Type: TABLE DATA; Schema: public; Owner: aayush
--

COPY public.hods (hod_id, hod_name, hod_email) FROM stdin;
1	Mamatha G S	hod.ise@rvce.edu.in
\.


--
-- Data for Name: lab_assistants; Type: TABLE DATA; Schema: public; Owner: aayush
--

COPY public.lab_assistants (lab_assistant_id, lab_assistant_name, lab_assistant_email, lab_assistant_dept, lab_assigned) FROM stdin;
1	Test Assistant	test@example.com	1	\N
2	Padmashree T	padmashreet@rvce.edu.in	1	\N
\.


--
-- Data for Name: labs; Type: TABLE DATA; Schema: public; Owner: aayush
--

COPY public.labs (lab_id, lab_dept, lab_number, assistant_ids) FROM stdin;
1	1	4	\N
\.


--
-- Data for Name: maintainence_logs; Type: TABLE DATA; Schema: public; Owner: aayush
--

COPY public.maintainence_logs (maintainence_id, system_id, date_at, is_acknowledged, acknowledged_at, acknowledged_by, resolved_at, severity, message) FROM stdin;
\.


--
-- Data for Name: metrics; Type: TABLE DATA; Schema: public; Owner: aayush
--

COPY public.metrics (metric_id, system_id, "timestamp", cpu_percent, cpu_temperature, ram_percent, disk_percent, disk_read_mbps, disk_write_mbps, network_sent_mbps, network_recv_mbps, gpu_percent, gpu_memory_used_gb, gpu_temperature, uptime_seconds, logged_in_users, cpu_iowait_percent, context_switch_rate, swap_in_rate, swap_out_rate, page_fault_rate, major_page_fault_rate) FROM stdin;
\.


--
-- Data for Name: network_scans; Type: TABLE DATA; Schema: public; Owner: aayush
--

COPY public.network_scans (scan_id, dept_id, scan_type, target_range, scan_start, scan_end, systems_found, status, error_message, scan_parameters, created_at) FROM stdin;
\.


--
-- Data for Name: performance_summaries; Type: TABLE DATA; Schema: public; Owner: aayush
--

COPY public.performance_summaries (summary_id, system_id, period_type, period_start, period_end, avg_cpu_percent, max_cpu_percent, min_cpu_percent, avg_ram_percent, max_ram_percent, avg_gpu_percent, max_gpu_percent, uptime_minutes, anomaly_count, created_at, stddev_cpu_percent, stddev_ram_percent, stddev_gpu_percent, stddev_disk_percent, min_ram_percent, min_gpu_percent, min_disk_percent, metric_count) FROM stdin;
\.


--
-- Data for Name: system_baselines; Type: TABLE DATA; Schema: public; Owner: aayush
--

COPY public.system_baselines (baseline_id, system_id, metric_name, baseline_mean, baseline_stddev, baseline_median, baseline_p95, baseline_start, baseline_end, sample_count, computed_at, is_active) FROM stdin;
\.


--
-- Data for Name: systems; Type: TABLE DATA; Schema: public; Owner: aayush
--

COPY public.systems (system_id, system_number, lab_id, dept_id, hostname, ip_address, mac_address, cpu_model, cpu_cores, ram_total_gb, disk_total_gb, gpu_model, gpu_memory, snmp_enabled, ssh_port, status, notes, created_at, updated_at) FROM stdin;
1	11	1	1	rvce-ThinkCentre-M75s-Gen-5	192.168.0.11	c4:ef:bb:8f:76:3c	AMD Ryzen 7 8700G w/ Radeon 780M Graphics	16	14.78	192.00	Card series	\N	f	22	offline	\N	2025-12-30 13:15:01.031703+05:30	2026-01-24 18:39:56.474516+05:30
3	10	1	1	rvce-ThinkCentre-neo-50t-Gen-3	192.168.0.10	e0:be:03:8a:ef:c6	12th Gen Intel(R) Core(TM) i7-12700	20	15.30	92.00	\N	\N	f	22	offline	\N	2026-01-20 11:44:01.715107+05:30	2026-01-24 18:39:56.474516+05:30
\.


--
-- Name: chunk_column_stats_id_seq; Type: SEQUENCE SET; Schema: _timescaledb_catalog; Owner: postgres
--

SELECT pg_catalog.setval('_timescaledb_catalog.chunk_column_stats_id_seq', 1, false);


--
-- Name: chunk_constraint_name; Type: SEQUENCE SET; Schema: _timescaledb_catalog; Owner: postgres
--

SELECT pg_catalog.setval('_timescaledb_catalog.chunk_constraint_name', 12, true);


--
-- Name: chunk_id_seq; Type: SEQUENCE SET; Schema: _timescaledb_catalog; Owner: postgres
--

SELECT pg_catalog.setval('_timescaledb_catalog.chunk_id_seq', 20, true);


--
-- Name: continuous_agg_migrate_plan_step_step_id_seq; Type: SEQUENCE SET; Schema: _timescaledb_catalog; Owner: postgres
--

SELECT pg_catalog.setval('_timescaledb_catalog.continuous_agg_migrate_plan_step_step_id_seq', 1, false);


--
-- Name: dimension_id_seq; Type: SEQUENCE SET; Schema: _timescaledb_catalog; Owner: postgres
--

SELECT pg_catalog.setval('_timescaledb_catalog.dimension_id_seq', 14, true);


--
-- Name: dimension_slice_id_seq; Type: SEQUENCE SET; Schema: _timescaledb_catalog; Owner: postgres
--

SELECT pg_catalog.setval('_timescaledb_catalog.dimension_slice_id_seq', 16, true);


--
-- Name: hypertable_id_seq; Type: SEQUENCE SET; Schema: _timescaledb_catalog; Owner: postgres
--

SELECT pg_catalog.setval('_timescaledb_catalog.hypertable_id_seq', 18, true);


--
-- Name: bgw_job_id_seq; Type: SEQUENCE SET; Schema: _timescaledb_config; Owner: postgres
--

SELECT pg_catalog.setval('_timescaledb_config.bgw_job_id_seq', 1009, true);


--
-- Name: collection_credentials_credential_id_seq; Type: SEQUENCE SET; Schema: public; Owner: aayush
--

SELECT pg_catalog.setval('public.collection_credentials_credential_id_seq', 1, false);


--
-- Name: departments_dept_id_seq; Type: SEQUENCE SET; Schema: public; Owner: aayush
--

SELECT pg_catalog.setval('public.departments_dept_id_seq', 2, true);


--
-- Name: hods_hod_id_seq; Type: SEQUENCE SET; Schema: public; Owner: aayush
--

SELECT pg_catalog.setval('public.hods_hod_id_seq', 1, true);


--
-- Name: lab_assistants_lab_assistant_id_seq; Type: SEQUENCE SET; Schema: public; Owner: aayush
--

SELECT pg_catalog.setval('public.lab_assistants_lab_assistant_id_seq', 2, true);


--
-- Name: labs_lab_id_seq; Type: SEQUENCE SET; Schema: public; Owner: aayush
--

SELECT pg_catalog.setval('public.labs_lab_id_seq', 1, true);


--
-- Name: maintainence_logs_maintainence_id_seq; Type: SEQUENCE SET; Schema: public; Owner: aayush
--

SELECT pg_catalog.setval('public.maintainence_logs_maintainence_id_seq', 151, true);


--
-- Name: metrics_metric_id_seq; Type: SEQUENCE SET; Schema: public; Owner: aayush
--

SELECT pg_catalog.setval('public.metrics_metric_id_seq', 2313, true);


--
-- Name: network_scans_scan_id_seq; Type: SEQUENCE SET; Schema: public; Owner: aayush
--

SELECT pg_catalog.setval('public.network_scans_scan_id_seq', 1, false);


--
-- Name: performance_summaries_summary_id_seq; Type: SEQUENCE SET; Schema: public; Owner: aayush
--

SELECT pg_catalog.setval('public.performance_summaries_summary_id_seq', 1, false);


--
-- Name: system_baselines_baseline_id_seq; Type: SEQUENCE SET; Schema: public; Owner: aayush
--

SELECT pg_catalog.setval('public.system_baselines_baseline_id_seq', 1, false);


--
-- Name: systems_system_id_seq; Type: SEQUENCE SET; Schema: public; Owner: aayush
--

SELECT pg_catalog.setval('public.systems_system_id_seq', 59, true);


--
-- Name: _hyper_13_1_chunk 1_1_metrics_pkey; Type: CONSTRAINT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_1_chunk
    ADD CONSTRAINT "1_1_metrics_pkey" PRIMARY KEY (system_id, "timestamp");


--
-- Name: _hyper_13_1_chunk 1_3_unique_system_timestamp; Type: CONSTRAINT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_1_chunk
    ADD CONSTRAINT "1_3_unique_system_timestamp" UNIQUE (system_id, "timestamp");


--
-- Name: _hyper_13_2_chunk 2_4_metrics_pkey; Type: CONSTRAINT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_2_chunk
    ADD CONSTRAINT "2_4_metrics_pkey" PRIMARY KEY (system_id, "timestamp");


--
-- Name: _hyper_13_2_chunk 2_6_unique_system_timestamp; Type: CONSTRAINT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_2_chunk
    ADD CONSTRAINT "2_6_unique_system_timestamp" UNIQUE (system_id, "timestamp");


--
-- Name: _hyper_13_3_chunk 3_7_metrics_pkey; Type: CONSTRAINT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_3_chunk
    ADD CONSTRAINT "3_7_metrics_pkey" PRIMARY KEY (system_id, "timestamp");


--
-- Name: _hyper_13_3_chunk 3_9_unique_system_timestamp; Type: CONSTRAINT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_3_chunk
    ADD CONSTRAINT "3_9_unique_system_timestamp" UNIQUE (system_id, "timestamp");


--
-- Name: _hyper_13_4_chunk 4_10_metrics_pkey; Type: CONSTRAINT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_4_chunk
    ADD CONSTRAINT "4_10_metrics_pkey" PRIMARY KEY (system_id, "timestamp");


--
-- Name: _hyper_13_4_chunk 4_12_unique_system_timestamp; Type: CONSTRAINT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_4_chunk
    ADD CONSTRAINT "4_12_unique_system_timestamp" UNIQUE (system_id, "timestamp");


--
-- Name: collection_credentials collection_credentials_credential_name_key; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.collection_credentials
    ADD CONSTRAINT collection_credentials_credential_name_key UNIQUE (credential_name);


--
-- Name: collection_credentials collection_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.collection_credentials
    ADD CONSTRAINT collection_credentials_pkey PRIMARY KEY (credential_id);


--
-- Name: departments departments_dept_name_key; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_dept_name_key UNIQUE (dept_name);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (dept_id);


--
-- Name: hods hods_hod_email_key; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.hods
    ADD CONSTRAINT hods_hod_email_key UNIQUE (hod_email);


--
-- Name: hods hods_pkey; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.hods
    ADD CONSTRAINT hods_pkey PRIMARY KEY (hod_id);


--
-- Name: lab_assistants lab_assistants_lab_assistant_email_key; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.lab_assistants
    ADD CONSTRAINT lab_assistants_lab_assistant_email_key UNIQUE (lab_assistant_email);


--
-- Name: lab_assistants lab_assistants_pkey; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.lab_assistants
    ADD CONSTRAINT lab_assistants_pkey PRIMARY KEY (lab_assistant_id);


--
-- Name: labs labs_pkey; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.labs
    ADD CONSTRAINT labs_pkey PRIMARY KEY (lab_id);


--
-- Name: maintainence_logs maintainence_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.maintainence_logs
    ADD CONSTRAINT maintainence_logs_pkey PRIMARY KEY (maintainence_id);


--
-- Name: metrics metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.metrics
    ADD CONSTRAINT metrics_pkey PRIMARY KEY (system_id, "timestamp");


--
-- Name: network_scans network_scans_pkey; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.network_scans
    ADD CONSTRAINT network_scans_pkey PRIMARY KEY (scan_id);


--
-- Name: performance_summaries performance_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.performance_summaries
    ADD CONSTRAINT performance_summaries_pkey PRIMARY KEY (summary_id);


--
-- Name: performance_summaries performance_summaries_system_id_period_type_period_start_key; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.performance_summaries
    ADD CONSTRAINT performance_summaries_system_id_period_type_period_start_key UNIQUE (system_id, period_type, period_start);


--
-- Name: system_baselines system_baselines_pkey; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.system_baselines
    ADD CONSTRAINT system_baselines_pkey PRIMARY KEY (baseline_id);


--
-- Name: system_baselines system_baselines_system_id_metric_name_baseline_start_basel_key; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.system_baselines
    ADD CONSTRAINT system_baselines_system_id_metric_name_baseline_start_basel_key UNIQUE (system_id, metric_name, baseline_start, baseline_end);


--
-- Name: systems systems_ip_address_key; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.systems
    ADD CONSTRAINT systems_ip_address_key UNIQUE (ip_address);


--
-- Name: systems systems_pkey; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.systems
    ADD CONSTRAINT systems_pkey PRIMARY KEY (system_id);


--
-- Name: metrics unique_system_timestamp; Type: CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.metrics
    ADD CONSTRAINT unique_system_timestamp UNIQUE (system_id, "timestamp");


--
-- Name: _hyper_13_1_chunk_idx_metrics_system_time; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_13_1_chunk_idx_metrics_system_time ON _timescaledb_internal._hyper_13_1_chunk USING btree (system_id, "timestamp" DESC);


--
-- Name: _hyper_13_1_chunk_idx_metrics_timestamp; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_13_1_chunk_idx_metrics_timestamp ON _timescaledb_internal._hyper_13_1_chunk USING btree ("timestamp" DESC);


--
-- Name: _hyper_13_2_chunk_idx_metrics_system_time; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_13_2_chunk_idx_metrics_system_time ON _timescaledb_internal._hyper_13_2_chunk USING btree (system_id, "timestamp" DESC);


--
-- Name: _hyper_13_2_chunk_idx_metrics_timestamp; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_13_2_chunk_idx_metrics_timestamp ON _timescaledb_internal._hyper_13_2_chunk USING btree ("timestamp" DESC);


--
-- Name: _hyper_13_3_chunk_idx_metrics_system_time; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_13_3_chunk_idx_metrics_system_time ON _timescaledb_internal._hyper_13_3_chunk USING btree (system_id, "timestamp" DESC);


--
-- Name: _hyper_13_3_chunk_idx_metrics_timestamp; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_13_3_chunk_idx_metrics_timestamp ON _timescaledb_internal._hyper_13_3_chunk USING btree ("timestamp" DESC);


--
-- Name: _hyper_13_4_chunk_idx_metrics_system_time; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_13_4_chunk_idx_metrics_system_time ON _timescaledb_internal._hyper_13_4_chunk USING btree (system_id, "timestamp" DESC);


--
-- Name: _hyper_13_4_chunk_idx_metrics_timestamp; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_13_4_chunk_idx_metrics_timestamp ON _timescaledb_internal._hyper_13_4_chunk USING btree ("timestamp" DESC);


--
-- Name: _hyper_17_14_chunk__materialized_hypertable_17_hour_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_17_14_chunk__materialized_hypertable_17_hour_bucket_idx ON _timescaledb_internal._hyper_17_14_chunk USING btree (hour_bucket DESC);


--
-- Name: _hyper_17_14_chunk__materialized_hypertable_17_system_id_hour_b; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_17_14_chunk__materialized_hypertable_17_system_id_hour_b ON _timescaledb_internal._hyper_17_14_chunk USING btree (system_id, hour_bucket DESC);


--
-- Name: _hyper_17_15_chunk__materialized_hypertable_17_hour_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_17_15_chunk__materialized_hypertable_17_hour_bucket_idx ON _timescaledb_internal._hyper_17_15_chunk USING btree (hour_bucket DESC);


--
-- Name: _hyper_17_15_chunk__materialized_hypertable_17_system_id_hour_b; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_17_15_chunk__materialized_hypertable_17_system_id_hour_b ON _timescaledb_internal._hyper_17_15_chunk USING btree (system_id, hour_bucket DESC);


--
-- Name: _hyper_17_16_chunk__materialized_hypertable_17_hour_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_17_16_chunk__materialized_hypertable_17_hour_bucket_idx ON _timescaledb_internal._hyper_17_16_chunk USING btree (hour_bucket DESC);


--
-- Name: _hyper_17_16_chunk__materialized_hypertable_17_system_id_hour_b; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_17_16_chunk__materialized_hypertable_17_system_id_hour_b ON _timescaledb_internal._hyper_17_16_chunk USING btree (system_id, hour_bucket DESC);


--
-- Name: _hyper_18_17_chunk__materialized_hypertable_18_day_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_18_17_chunk__materialized_hypertable_18_day_bucket_idx ON _timescaledb_internal._hyper_18_17_chunk USING btree (day_bucket DESC);


--
-- Name: _hyper_18_17_chunk__materialized_hypertable_18_system_id_day_bu; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_18_17_chunk__materialized_hypertable_18_system_id_day_bu ON _timescaledb_internal._hyper_18_17_chunk USING btree (system_id, day_bucket DESC);


--
-- Name: _hyper_18_18_chunk__materialized_hypertable_18_day_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_18_18_chunk__materialized_hypertable_18_day_bucket_idx ON _timescaledb_internal._hyper_18_18_chunk USING btree (day_bucket DESC);


--
-- Name: _hyper_18_18_chunk__materialized_hypertable_18_system_id_day_bu; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_18_18_chunk__materialized_hypertable_18_system_id_day_bu ON _timescaledb_internal._hyper_18_18_chunk USING btree (system_id, day_bucket DESC);


--
-- Name: _hyper_18_19_chunk__materialized_hypertable_18_day_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_18_19_chunk__materialized_hypertable_18_day_bucket_idx ON _timescaledb_internal._hyper_18_19_chunk USING btree (day_bucket DESC);


--
-- Name: _hyper_18_19_chunk__materialized_hypertable_18_system_id_day_bu; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _hyper_18_19_chunk__materialized_hypertable_18_system_id_day_bu ON _timescaledb_internal._hyper_18_19_chunk USING btree (system_id, day_bucket DESC);


--
-- Name: _materialized_hypertable_17_hour_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _materialized_hypertable_17_hour_bucket_idx ON _timescaledb_internal._materialized_hypertable_17 USING btree (hour_bucket DESC);


--
-- Name: _materialized_hypertable_17_system_id_hour_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _materialized_hypertable_17_system_id_hour_bucket_idx ON _timescaledb_internal._materialized_hypertable_17 USING btree (system_id, hour_bucket DESC);


--
-- Name: _materialized_hypertable_18_day_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _materialized_hypertable_18_day_bucket_idx ON _timescaledb_internal._materialized_hypertable_18 USING btree (day_bucket DESC);


--
-- Name: _materialized_hypertable_18_system_id_day_bucket_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX _materialized_hypertable_18_system_id_day_bucket_idx ON _timescaledb_internal._materialized_hypertable_18 USING btree (system_id, day_bucket DESC);


--
-- Name: compress_hyper_14_11_chunk_system_id__ts_meta_min_1__ts_met_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX compress_hyper_14_11_chunk_system_id__ts_meta_min_1__ts_met_idx ON _timescaledb_internal.compress_hyper_14_11_chunk USING btree (system_id, _ts_meta_min_1 DESC, _ts_meta_max_1 DESC);


--
-- Name: compress_hyper_14_12_chunk_system_id__ts_meta_min_1__ts_met_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX compress_hyper_14_12_chunk_system_id__ts_meta_min_1__ts_met_idx ON _timescaledb_internal.compress_hyper_14_12_chunk USING btree (system_id, _ts_meta_min_1 DESC, _ts_meta_max_1 DESC);


--
-- Name: compress_hyper_14_13_chunk_system_id__ts_meta_min_1__ts_met_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX compress_hyper_14_13_chunk_system_id__ts_meta_min_1__ts_met_idx ON _timescaledb_internal.compress_hyper_14_13_chunk USING btree (system_id, _ts_meta_min_1 DESC, _ts_meta_max_1 DESC);


--
-- Name: compress_hyper_14_20_chunk_system_id__ts_meta_min_1__ts_met_idx; Type: INDEX; Schema: _timescaledb_internal; Owner: aayush
--

CREATE INDEX compress_hyper_14_20_chunk_system_id__ts_meta_min_1__ts_met_idx ON _timescaledb_internal.compress_hyper_14_20_chunk USING btree (system_id, _ts_meta_min_1 DESC, _ts_meta_max_1 DESC);


--
-- Name: idx_alert_logs_severity; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_alert_logs_severity ON public.maintainence_logs USING btree (severity);


--
-- Name: idx_alert_logs_system; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_alert_logs_system ON public.maintainence_logs USING btree (system_id);


--
-- Name: idx_alert_logs_triggered; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_alert_logs_triggered ON public.maintainence_logs USING btree (date_at DESC);


--
-- Name: idx_alert_logs_unresolved; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_alert_logs_unresolved ON public.maintainence_logs USING btree (resolved_at) WHERE (resolved_at IS NULL);


--
-- Name: idx_baselines_computed; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_baselines_computed ON public.system_baselines USING btree (computed_at DESC);


--
-- Name: idx_baselines_system_metric; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_baselines_system_metric ON public.system_baselines USING btree (system_id, metric_name, is_active);


--
-- Name: idx_metrics_system_time; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_metrics_system_time ON public.metrics USING btree (system_id, "timestamp" DESC);


--
-- Name: idx_metrics_system_timestamp; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_metrics_system_timestamp ON public.metrics USING btree (system_id, "timestamp" DESC);


--
-- Name: idx_metrics_timestamp; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_metrics_timestamp ON public.metrics USING btree ("timestamp" DESC);


--
-- Name: idx_network_scans_dept; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_network_scans_dept ON public.network_scans USING btree (dept_id);


--
-- Name: idx_network_scans_start; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_network_scans_start ON public.network_scans USING btree (scan_start DESC);


--
-- Name: idx_network_scans_status; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_network_scans_status ON public.network_scans USING btree (status);


--
-- Name: idx_perf_summary_period_type; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_perf_summary_period_type ON public.performance_summaries USING btree (period_type, period_start DESC);


--
-- Name: idx_perf_summary_system_period; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_perf_summary_system_period ON public.performance_summaries USING btree (system_id, period_start DESC);


--
-- Name: idx_systems_dept; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_systems_dept ON public.systems USING btree (dept_id);


--
-- Name: idx_systems_hostname; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_systems_hostname ON public.systems USING btree (hostname);


--
-- Name: idx_systems_ip; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_systems_ip ON public.systems USING gist (ip_address inet_ops);


--
-- Name: idx_systems_mac; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_systems_mac ON public.systems USING btree (mac_address);


--
-- Name: idx_systems_status; Type: INDEX; Schema: public; Owner: aayush
--

CREATE INDEX idx_systems_status ON public.systems USING btree (status);


--
-- Name: _hyper_13_1_chunk trg_cpu_overload; Type: TRIGGER; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TRIGGER trg_cpu_overload AFTER INSERT ON _timescaledb_internal._hyper_13_1_chunk FOR EACH ROW EXECUTE FUNCTION public.detect_sustained_cpu_overload();


--
-- Name: _hyper_13_2_chunk trg_cpu_overload; Type: TRIGGER; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TRIGGER trg_cpu_overload AFTER INSERT ON _timescaledb_internal._hyper_13_2_chunk FOR EACH ROW EXECUTE FUNCTION public.detect_sustained_cpu_overload();


--
-- Name: _hyper_13_3_chunk trg_cpu_overload; Type: TRIGGER; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TRIGGER trg_cpu_overload AFTER INSERT ON _timescaledb_internal._hyper_13_3_chunk FOR EACH ROW EXECUTE FUNCTION public.detect_sustained_cpu_overload();


--
-- Name: _hyper_13_4_chunk trg_cpu_overload; Type: TRIGGER; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TRIGGER trg_cpu_overload AFTER INSERT ON _timescaledb_internal._hyper_13_4_chunk FOR EACH ROW EXECUTE FUNCTION public.detect_sustained_cpu_overload();


--
-- Name: _hyper_13_1_chunk trg_metrics_update_status; Type: TRIGGER; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TRIGGER trg_metrics_update_status AFTER INSERT ON _timescaledb_internal._hyper_13_1_chunk FOR EACH ROW EXECUTE FUNCTION public.update_system_status();


--
-- Name: _hyper_13_2_chunk trg_metrics_update_status; Type: TRIGGER; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TRIGGER trg_metrics_update_status AFTER INSERT ON _timescaledb_internal._hyper_13_2_chunk FOR EACH ROW EXECUTE FUNCTION public.update_system_status();


--
-- Name: _hyper_13_3_chunk trg_metrics_update_status; Type: TRIGGER; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TRIGGER trg_metrics_update_status AFTER INSERT ON _timescaledb_internal._hyper_13_3_chunk FOR EACH ROW EXECUTE FUNCTION public.update_system_status();


--
-- Name: _hyper_13_4_chunk trg_metrics_update_status; Type: TRIGGER; Schema: _timescaledb_internal; Owner: aayush
--

CREATE TRIGGER trg_metrics_update_status AFTER INSERT ON _timescaledb_internal._hyper_13_4_chunk FOR EACH ROW EXECUTE FUNCTION public.update_system_status();


--
-- Name: metrics trg_cpu_overload; Type: TRIGGER; Schema: public; Owner: aayush
--

CREATE TRIGGER trg_cpu_overload AFTER INSERT ON public.metrics FOR EACH ROW EXECUTE FUNCTION public.detect_sustained_cpu_overload();


--
-- Name: departments trg_departments_updated_at; Type: TRIGGER; Schema: public; Owner: aayush
--

CREATE TRIGGER trg_departments_updated_at BEFORE UPDATE ON public.departments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: metrics trg_metrics_update_status; Type: TRIGGER; Schema: public; Owner: aayush
--

CREATE TRIGGER trg_metrics_update_status AFTER INSERT ON public.metrics FOR EACH ROW EXECUTE FUNCTION public.update_system_status();


--
-- Name: systems trg_systems_updated_at; Type: TRIGGER; Schema: public; Owner: aayush
--

CREATE TRIGGER trg_systems_updated_at BEFORE UPDATE ON public.systems FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: _hyper_13_1_chunk 1_2_metrics_system_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_1_chunk
    ADD CONSTRAINT "1_2_metrics_system_id_fkey" FOREIGN KEY (system_id) REFERENCES public.systems(system_id) ON DELETE CASCADE;


--
-- Name: _hyper_13_2_chunk 2_5_metrics_system_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_2_chunk
    ADD CONSTRAINT "2_5_metrics_system_id_fkey" FOREIGN KEY (system_id) REFERENCES public.systems(system_id) ON DELETE CASCADE;


--
-- Name: _hyper_13_3_chunk 3_8_metrics_system_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_3_chunk
    ADD CONSTRAINT "3_8_metrics_system_id_fkey" FOREIGN KEY (system_id) REFERENCES public.systems(system_id) ON DELETE CASCADE;


--
-- Name: _hyper_13_4_chunk 4_11_metrics_system_id_fkey; Type: FK CONSTRAINT; Schema: _timescaledb_internal; Owner: aayush
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_4_chunk
    ADD CONSTRAINT "4_11_metrics_system_id_fkey" FOREIGN KEY (system_id) REFERENCES public.systems(system_id) ON DELETE CASCADE;


--
-- Name: departments departments_hod_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_hod_id_fkey FOREIGN KEY (hod_id) REFERENCES public.hods(hod_id) ON DELETE SET NULL;


--
-- Name: lab_assistants lab_assistants_lab_assigned_fkey; Type: FK CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.lab_assistants
    ADD CONSTRAINT lab_assistants_lab_assigned_fkey FOREIGN KEY (lab_assigned) REFERENCES public.labs(lab_id) ON DELETE SET NULL;


--
-- Name: lab_assistants lab_assistants_lab_assistant_dept_fkey; Type: FK CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.lab_assistants
    ADD CONSTRAINT lab_assistants_lab_assistant_dept_fkey FOREIGN KEY (lab_assistant_dept) REFERENCES public.departments(dept_id) ON DELETE SET NULL;


--
-- Name: labs labs_lab_dept_fkey; Type: FK CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.labs
    ADD CONSTRAINT labs_lab_dept_fkey FOREIGN KEY (lab_dept) REFERENCES public.departments(dept_id) ON DELETE CASCADE;


--
-- Name: maintainence_logs maintainence_logs_system_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.maintainence_logs
    ADD CONSTRAINT maintainence_logs_system_id_fkey FOREIGN KEY (system_id) REFERENCES public.systems(system_id) ON DELETE CASCADE;


--
-- Name: metrics metrics_system_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.metrics
    ADD CONSTRAINT metrics_system_id_fkey FOREIGN KEY (system_id) REFERENCES public.systems(system_id) ON DELETE CASCADE;


--
-- Name: network_scans network_scans_dept_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.network_scans
    ADD CONSTRAINT network_scans_dept_id_fkey FOREIGN KEY (dept_id) REFERENCES public.departments(dept_id) ON DELETE CASCADE;


--
-- Name: performance_summaries performance_summaries_system_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.performance_summaries
    ADD CONSTRAINT performance_summaries_system_id_fkey FOREIGN KEY (system_id) REFERENCES public.systems(system_id) ON DELETE CASCADE;


--
-- Name: system_baselines system_baselines_system_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.system_baselines
    ADD CONSTRAINT system_baselines_system_id_fkey FOREIGN KEY (system_id) REFERENCES public.systems(system_id) ON DELETE CASCADE;


--
-- Name: systems systems_dept_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.systems
    ADD CONSTRAINT systems_dept_id_fkey FOREIGN KEY (dept_id) REFERENCES public.departments(dept_id) ON DELETE SET NULL;


--
-- Name: systems systems_lab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: aayush
--

ALTER TABLE ONLY public.systems
    ADD CONSTRAINT systems_lab_id_fkey FOREIGN KEY (lab_id) REFERENCES public.labs(lab_id) ON DELETE SET NULL;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: aayush
--

ALTER DEFAULT PRIVILEGES FOR ROLE aayush IN SCHEMA public GRANT ALL ON TABLES TO aayush;


--
-- PostgreSQL database dump complete
--

\unrestrict RulEVreLDOunijRdFkF9qi6o2Zvh5ecoEDdn3Bwv9OgrDQjzklVAOFBfcKpHe33

