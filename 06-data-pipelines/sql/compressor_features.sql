-- Daily feature table for the compressor failure model (7-day horizon label from SAP PM failures)
CREATE OR REPLACE TABLE `${DATA}.features.compressor_daily` AS
WITH daily AS (
  SELECT DATE(minute) AS day, asset_id,
    AVG(IF(ENDS_WITH(tag, 'vib_de_mm_s'), avg_v, NULL))    AS vib_mean,
    MAX(IF(ENDS_WITH(tag, 'vib_de_mm_s'), max_v, NULL))    AS vib_max,
    STDDEV(IF(ENDS_WITH(tag, 'vib_de_mm_s'), avg_v, NULL)) AS vib_std,
    AVG(IF(ENDS_WITH(tag, 'bearing_temp_c'), avg_v, NULL)) AS temp_mean,
    MAX(IF(ENDS_WITH(tag, 'bearing_temp_c'), max_v, NULL)) AS temp_max,
    AVG(IF(ENDS_WITH(tag, 'disch_press_bar'), avg_v, NULL)) AS press_mean
  FROM `${DATA}.curated.telemetry_1m`
  WHERE asset_id LIKE 'K-%'
  GROUP BY 1, 2
)
SELECT d.*,
  vib_mean - AVG(vib_mean) OVER w7  AS vib_delta_7d,
  temp_mean - AVG(temp_mean) OVER w7 AS temp_delta_7d,
  EXISTS (SELECT 1 FROM `${DATA}.marts.failures` f
          WHERE f.asset_id = d.asset_id AND f.failure_date BETWEEN d.day AND DATE_ADD(d.day, INTERVAL 7 DAY)) AS label_fail_7d
FROM daily d
WINDOW w7 AS (PARTITION BY asset_id ORDER BY UNIX_DATE(day) RANGE BETWEEN 7 PRECEDING AND 1 PRECEDING);
