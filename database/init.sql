-- CREATE DATABASE credit_limit_db;
-- GRANT ALL PRIVILEGES ON DATABASE sumup TO postgres;
-- CREATE USER sumapp WITH PASSWORD 'sumapp';
-- GRANT ALL PRIVILEGES ON DATABASE credit_limit_db TO sumapp;
-- ALTER USER sumapp_admin with PASSWORD 'very_secure_admin_password';

-- \c credit_limit_db;
--
-- CREATE TABLE credit_score (
-- 	user_id bigint,
-- 	name varchar(255),
-- 	store_name varchar(255),
-- 	credit_limit numeric(16, 3)
-- );
-- COPY credit_score FROM '/tmp/data/snapshot_20230101.csv' DELIMITER ',' CSV HEADER;
-- COPY credit_score FROM '/tmp/data/snapshot_20230603.csv' DELIMITER ',' CSV HEADER;
--
-- CREATE INDEX idx_user_id_credit_score ON credit_score(user_id);

CREATE SCHEMA staging;

SET search_path = staging, public;

CREATE TABLE staging.cohorts (
    id INT PRIMARY KEY,
    name VARCHAR(255),
    project_id INT
);

CREATE TABLE staging.devices (
    id INT PRIMARY KEY,
    project_id INT,
    device_serial VARCHAR(255),
    cohort_id INT
);

CREATE TABLE staging.events (
    id INT PRIMARY KEY,
    project_id INT,
    captured_date TIMESTAMP WITH TIME ZONE,
    created_date TIMESTAMP WITH TIME ZONE,
    type VARCHAR(255),
    software_version_id INT,
    device_id INT,
    event_info JSONB
);

CREATE TABLE staging.software_versions (
    id INT PRIMARY KEY,
    project_id INT,
    version VARCHAR(255)
);

COPY staging.cohorts FROM '/tmp/data/cohorts.csv' DELIMITER E'\t' CSV HEADER;
COPY staging.devices FROM '/tmp/data/devices.csv' DELIMITER E'\t' CSV HEADER;
COPY staging.events FROM '/tmp/data/events.csv' DELIMITER E'\t' CSV HEADER;
COPY staging.software_versions FROM '/tmp/data/software_versions.csv' DELIMITER E'\t' CSV HEADER;

CREATE SCHEMA params;

CREATE TABLE params.load_log(
    table_name VARCHAR(255) PRIMARY KEY,
    last_loaded TIMESTAMP WITH TIME ZONE DEFAULT '-infinity'
);
insert into params.load_log values('heartbeat');

CREATE SCHEMA curated;
CREATE TABLE curated.heartbeat (
    event_id INT,
    project_id INT,
    device_id INT,
    captured_date TIMESTAMP WITH TIME ZONE,
    created_date TIMESTAMP WITH TIME ZONE,
    software_version_id INT,
    version VARCHAR(255),
    device_serial VARCHAR(255),
    cohort_id INT,
    cohort_name VARCHAR(255),
    metrics JSONB
)  PARTITION BY RANGE (captured_date);

CREATE MATERIALIZED VIEW curated.battery_percentile AS
SELECT
    CAST(captured_date AS date) AS captured_dt,
    project_id,
    CAST(metrics -> 'battery_perc' AS int) / 10 AS battery_perc,
    COUNT(*) AS cnt
FROM curated.heartbeat
GROUP BY captured_dt, project_id, battery_perc;

CREATE INDEX idx_project_id ON curated.battery_percentile (project_id);