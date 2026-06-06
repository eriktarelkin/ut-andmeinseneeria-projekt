TRUNCATE TABLE quality.test_results;

WITH latest_run AS (
    SELECT run_id
    FROM staging.pipeline_runs
    WHERE status = 'success'
    ORDER BY fetched_at DESC
    LIMIT 1
),
test_cases AS (
    SELECT
        'dim_maakond_has_rows' AS test_name,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM mart.dim_maakond
            )
                THEN 0
            ELSE 1
        END AS failed_rows,
        'Maakondade dimensioonis peab olema vähemalt üks rida.' AS message

    UNION ALL

    SELECT
        'fact_skoor_has_rows' AS test_name,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM mart.fact_skoor
            )
                THEN 0
            ELSE 1
        END AS failed_rows,
        'Skooride tabelis peab olema vähemalt üks rida.' AS message

    UNION ALL

    SELECT
        'raw_tu110_latest_run_has_rows' AS test_name,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM staging.raw_tu110 AS t
                INNER JOIN latest_run AS r ON t.run_id = r.run_id
            )
                THEN 0
            ELSE 1
        END AS failed_rows,
        'Viimasel edukal laadimisel peab olema vähemalt üks rida staging.raw_tu110-s.' AS message

    UNION ALL

    SELECT
        'loplik_skoor_not_null' AS test_name,
        COUNT(*)::integer AS failed_rows,
        'Lõplik skoor ei tohi olla NULL.' AS message
    FROM mart.fact_skoor AS s
    WHERE s.loplik_skoor IS NULL

    UNION ALL

    SELECT
        'loplik_skoor_range' AS test_name,
        COUNT(*)::integer AS failed_rows,
        'Lõplik skoor peab jääma vahemikku 0 kuni 1.' AS message
    FROM mart.fact_skoor AS s
    WHERE s.loplik_skoor NOT BETWEEN 0 AND 1

    UNION ALL

    SELECT
        'norm_values_range' AS test_name,
        COUNT(*)::integer AS failed_rows,
        'Normaliseeritud väärtused peavad jääma vahemikku 0 kuni 1.' AS message
    FROM mart.fact_skoor AS s
    WHERE s.turumaht_norm             NOT BETWEEN 0 AND 1
       OR s.taitumus_norm             NOT BETWEEN 0 AND 1
       OR s.rahaline_potentsiaal_norm NOT BETWEEN 0 AND 1

    UNION ALL

    SELECT
        'hinnang_id_valid' AS test_name,
        COUNT(*)::integer AS failed_rows,
        'Äriline hinnang peab olema vahemikus 1 kuni 4.' AS message
    FROM mart.fact_skoor AS s
    WHERE s.hinnang_id NOT IN (1, 2, 3, 4)

    UNION ALL

    SELECT
        'weights_sum_to_one' AS test_name,
        COUNT(*)::integer AS failed_rows,
        'Kaalud peavad summeeruma 1.0-ks (±0.01).' AS message
    FROM mart.fact_skoor AS s
    WHERE ABS(s.w1_turumaht + s.w3_taitumus + s.w4_rahaline - 1.0) > 0.01

    UNION ALL

    SELECT
        'no_orphaned_fact_skoor' AS test_name,
        COUNT(*)::integer AS failed_rows,
        'Kõik fact_skoor maakond_id-d peavad eksisteerima dim_maakond-is.' AS message
    FROM mart.fact_skoor AS s
    LEFT JOIN mart.dim_maakond AS m ON s.maakond_id = m.maakond_id
    WHERE m.maakond_id IS NULL

    UNION ALL

    SELECT
        'unique_maakond_in_fact_skoor' AS test_name,
        COUNT(*)::integer AS failed_rows,
        'fact_skoor-is tohib olla iga maakonna kohta täpselt üks rida.' AS message
    FROM (
        SELECT
            s.maakond_id,
            COUNT(*) AS row_count
        FROM mart.fact_skoor AS s
        GROUP BY s.maakond_id
        HAVING COUNT(*) > 1
    ) AS duplicates

    UNION ALL

    SELECT
        'fact_oobimised_no_negative_oobimised' AS test_name,
        COUNT(*)::integer AS failed_rows,
        'Ööbimiste arv ei tohi olla negatiivne.' AS message
    FROM mart.fact_oobimised AS f
    WHERE f.oobimiste_arv < 0

    UNION ALL

    SELECT
        'fact_oobimised_taitumus_proxy_range' AS test_name,
        COUNT(*)::integer AS failed_rows,
        'Täituvuse proxy peab jääma vahemikku 0 kuni 1.' AS message
    FROM mart.fact_oobimised AS f
    WHERE f.taitumus_proxy IS NOT NULL
      AND f.taitumus_proxy NOT BETWEEN 0 AND 1
)
INSERT INTO quality.test_results (
    test_name,
    status,
    failed_rows,
    message
)
SELECT
    test_name,
    CASE WHEN failed_rows = 0 THEN 'passed' ELSE 'failed' END AS status,
    failed_rows,
    message
FROM test_cases
ORDER BY test_name;
