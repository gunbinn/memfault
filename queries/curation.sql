BEGIN;

-- Partitions managing in Postgres is a disaster. But I believe we definitely need it here.
-- Although staging data is partitioned by created date, for curated layer I chose to use captured_date for partitioning.
-- As I believe it will be extensively used for business metrics.
DO $$
DECLARE
    new_day DATE;
BEGIN
    FOR new_day IN (
        SELECT DISTINCT DATE_TRUNC('day', captured_date) AS new_day
        FROM staging.events ev
        WHERE ev.type = 'heartbeat'
        AND ev.created_date > (SELECT MAX(last_loaded) FROM params.load_log WHERE table_name = 'heartbeat')
    )
    LOOP
        DECLARE
            index_name TEXT;
            partition_name TEXT;
        BEGIN
            partition_name := 'curated.heartbeat_' || to_char(new_day, 'YYYY_MM_DD');
            index_name := 'idx_project_id_' || to_char(new_day, 'YYYY_MM_DD');

            EXECUTE 'CREATE TABLE IF NOT EXISTS ' || partition_name ||
                    ' PARTITION OF curated.heartbeat FOR VALUES FROM (''' || new_day || '''::date) TO (''' || (new_day + INTERVAL '1 day') || '''::date)';

            EXECUTE 'CREATE INDEX IF NOT EXISTS ' || index_name ||
                    ' ON ' || partition_name || ' (project_id)';
        END;
    END LOOP;
END;
$$;


INSERT INTO curated.heartbeat
SELECT
       ev.id AS event_id,
       ev.project_id,
       ev.device_id,
       ev.captured_date,
       ev.created_date,
       ev.software_version_id,
       ver.version,
       dev.device_serial,
       dev.cohort_id,
       coh.name AS cohort_name,
       event_info->'metrics' AS metrics
FROM staging.events ev
LEFT JOIN params.load_log log
    ON log.table_name = 'heartbeat'
LEFT JOIN staging.devices dev ON ev.device_id = dev.id
LEFT JOIN staging.software_versions ver ON ev.software_version_id = ver.id
LEFT JOIN staging.cohorts coh ON dev.cohort_id = coh.id
WHERE ev.type = 'heartbeat'
AND ev.created_date > log.last_loaded;


UPDATE params.load_log
    SET last_loaded = coalesce((select max(created_date) from curated.heartbeat), '-infinity')
where table_name = 'heartbeat';

REFRESH MATERIALIZED VIEW curated.battery_percentile;

COMMIT;