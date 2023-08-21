CREATE OR REPLACE FUNCTION calculate_battery_percentile(
    percentile numeric,
    param_project_id integer,
    start_dt date,
    end_dt date
) RETURNS numeric AS
$$
DECLARE
    result numeric;
BEGIN
    WITH
    bin_agg AS (
        SELECT
            battery_perc,
            SUM(cnt) AS bin_cnt
        FROM curated.battery_percentile
        WHERE captured_dt BETWEEN start_dt AND end_dt
            AND project_id = param_project_id
        GROUP BY battery_perc
    ),
    period_agg AS (
        SELECT
            battery_perc,
            bin_cnt,
            SUM(bin_cnt) OVER (ORDER BY battery_perc) as cum_sum,
            SUM(bin_cnt) OVER () as total
        FROM bin_agg
    )
    SELECT AVG(battery_perc)
    INTO result
    FROM period_agg
    WHERE cum_sum >= total * percentile
      AND cum_sum - bin_cnt < total * percentile;

    RETURN result;
END;
$$ LANGUAGE plpgsql;

SELECT calculate_battery_percentile(0.5, 367, '2021-01-01', '2023-01-31') AS median_battery_perc;
