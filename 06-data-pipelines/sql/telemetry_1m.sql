-- Scheduled query (every 15 min): 1-minute aggregates for dashboards and features
MERGE `${DATA}.curated.telemetry_1m` t
USING (
  SELECT TIMESTAMP_TRUNC(ts, MINUTE) AS minute, site, asset_id, tag,
         AVG(value) AS avg_v, MIN(value) AS min_v, MAX(value) AS max_v, COUNT(*) AS n
  FROM `${DATA}.curated.telemetry`
  WHERE ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 MINUTE) AND quality = 'GOOD'
  GROUP BY 1, 2, 3, 4
) s
ON t.minute = s.minute AND t.tag = s.tag
WHEN MATCHED THEN UPDATE SET avg_v = s.avg_v, min_v = s.min_v, max_v = s.max_v, n = s.n
WHEN NOT MATCHED THEN INSERT ROW;
