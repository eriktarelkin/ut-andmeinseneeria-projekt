-- Hetkel lisame vaid maakonna nime tabelisse, 
-- oleks vaja mõelda kuidas teisi andmeid ka sisestada

-- All on tabelikuju, mis me soovime
/* CREATE TABLE IF NOT EXISTS mart.dim_maakond (
    maakond_id      serial PRIMARY KEY
    maakond_nimi    text NOT NULL UNIQUE,           
    maakond_lyhend  text,                   
    regioon         text,    
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamp DEFAULT now()
); */


INSERT INTO mart.dim_maakond (maakond_nimi)
SELECT DISTINCT maakond
FROM staging.raw_tu110
ON CONFLICT (maakond_nimi) DO NOTHING;


INSERT INTO mart.fact_oobimised (
    maakond_id,
    aasta,
    majutuskohti_arv,
    tubade_arv,
    voodikohtade_arv,
    majutatute_arv,
    oobimiste_arv,
    tubade_taitumus_pct,
    voodikohtade_taitumus_pct,
    oopaeva_keskmine_maksumus
)
SELECT
    m.maakond_id,
    r.aasta,
    r.majutuskohti_arv,
    r.tubade_arv,
    r.voodikohtade_arv,
    r.majutatute_arv,
    r.oobimiste_arv,
    r.tubade_taitumus_pct,
    r.voodikohtade_taitumus_pct,
    r.oopaeva_keskmine_maksumus
FROM staging.raw_tu110 r
JOIN mart.dim_maakond m
    ON m.maakond_nimi = r.maakond
ON CONFLICT (maakond_id, aasta) DO UPDATE SET
    majutuskohti_arv = EXCLUDED.majutuskohti_arv,
    tubade_arv = EXCLUDED.tubade_arv,
    voodikohtade_arv = EXCLUDED.voodikohtade_arv,
    majutatute_arv = EXCLUDED.majutatute_arv,
    oobimiste_arv = EXCLUDED.oobimiste_arv,
    tubade_taitumus_pct = EXCLUDED.tubade_taitumus_pct,
    voodikohtade_taitumus_pct = EXCLUDED.voodikohtade_taitumus_pct,
    oopaeva_keskmine_maksumus = EXCLUDED.oopaeva_keskmine_maksumus,
    loaded_at = now();


-- =========================
-- 3. SCORE TABLE (1 aasta — CAGR lisatakse hiljem)
-- =========================

WITH latest AS (
    SELECT MAX(aasta) AS latest_year
    FROM mart.fact_oobimised
),

-- Kaalud loetakse mart.fact_skoor tabelist; uutel ridadel kasutatakse vaikeväärtusi.
-- w2_kasv (CAGR) jäetakse siia vahele — CAGR pole veel saadaval.
kaalud AS (
    SELECT
        m.maakond_id,
        COALESCE(fs.w1_turumaht, 0.40) AS w1_turumaht,
        COALESCE(fs.w3_taitumus, 0.35) AS w3_taitumus,
        COALESCE(fs.w4_rahaline, 0.25) AS w4_rahaline
    FROM mart.dim_maakond m
    LEFT JOIN mart.fact_skoor fs ON fs.maakond_id = m.maakond_id
),

baas AS (
    SELECT
        f.maakond_id,
        MAX(f.oobimiste_arv)                                           FILTER (WHERE f.aasta = latest.latest_year) AS turumaht_raw,
        MAX(f.taitumus_proxy)                                          FILTER (WHERE f.aasta = latest.latest_year) AS taitumus_raw,
        MAX(f.oobimiste_arv * f.oopaeva_keskmine_maksumus)            FILTER (WHERE f.aasta = latest.latest_year) AS rahaline_potentsiaal_raw
    FROM mart.fact_oobimised f
    CROSS JOIN latest
    GROUP BY f.maakond_id
),

minmax AS (
    SELECT
        MIN(turumaht_raw) AS turumaht_min, MAX(turumaht_raw) AS turumaht_max,
        MIN(taitumus_raw) AS taitumus_min, MAX(taitumus_raw) AS taitumus_max,
        MIN(rahaline_potentsiaal_raw) AS raha_min, MAX(rahaline_potentsiaal_raw) AS raha_max
    FROM baas
),

norm AS (
    SELECT
        c.*,
        k.w1_turumaht,
        k.w3_taitumus,
        k.w4_rahaline,
        CASE WHEN m.turumaht_max > m.turumaht_min
            THEN (c.turumaht_raw - m.turumaht_min) / (m.turumaht_max - m.turumaht_min)
            ELSE 0.5 END AS turumaht_norm,
        CASE WHEN m.taitumus_max > m.taitumus_min
            THEN (c.taitumus_raw - m.taitumus_min) / (m.taitumus_max - m.taitumus_min)
            ELSE 0.5 END AS taitumus_norm,
        CASE WHEN m.raha_max > m.raha_min
            THEN (c.rahaline_potentsiaal_raw - m.raha_min) / (m.raha_max - m.raha_min)
            ELSE 0.5 END AS rahaline_potentsiaal_norm
    FROM baas c
    CROSS JOIN minmax m
    JOIN kaalud k ON k.maakond_id = c.maakond_id
),

scored AS (
    SELECT
        *,
        ROUND(
            (w1_turumaht * turumaht_norm) +
            (w3_taitumus * taitumus_norm) +
            (w4_rahaline * rahaline_potentsiaal_norm)
        , 4) AS loplik_skoor
    FROM norm
),

hinnang AS (
    SELECT
        *,
        CASE
            WHEN loplik_skoor >= 0.65                           THEN 1  -- Atraktiivne: kõrge koondskoor
            WHEN taitumus_norm >= 0.6 AND turumaht_norm < 0.4   THEN 2  -- Kasvav: kõrge nõudlus/pakkumine, väike maht
            WHEN taitumus_norm < 0.35 AND turumaht_norm < 0.4   THEN 3  -- Küllastunud: madal täituvus ja maht
            ELSE                                                 4  -- Stabiilne rahavoog
        END AS hinnang_id
    FROM scored
)

INSERT INTO mart.fact_skoor (
    maakond_id,
    turumaht_raw,
    cagr_raw,
    taitumus_raw,
    rahaline_potentsiaal_raw,
    turumaht_norm,
    cagr_norm,
    taitumus_norm,
    rahaline_potentsiaal_norm,
    loplik_skoor,
    hinnang_id,
    w1_turumaht,
    w3_taitumus,
    w4_rahaline
)
SELECT
    maakond_id,
    turumaht_raw,
    NULL AS cagr_raw,
    taitumus_raw,
    rahaline_potentsiaal_raw,
    turumaht_norm,
    NULL AS cagr_norm,
    taitumus_norm,
    rahaline_potentsiaal_norm,
    loplik_skoor,
    hinnang_id,
    w1_turumaht,
    w3_taitumus,
    w4_rahaline
FROM hinnang
ON CONFLICT (maakond_id) DO UPDATE SET
    turumaht_raw              = EXCLUDED.turumaht_raw,
    cagr_raw                  = NULL,
    taitumus_raw              = EXCLUDED.taitumus_raw,
    rahaline_potentsiaal_raw  = EXCLUDED.rahaline_potentsiaal_raw,
    turumaht_norm             = EXCLUDED.turumaht_norm,
    cagr_norm                 = NULL,
    taitumus_norm             = EXCLUDED.taitumus_norm,
    rahaline_potentsiaal_norm = EXCLUDED.rahaline_potentsiaal_norm,
    loplik_skoor              = EXCLUDED.loplik_skoor,
    hinnang_id                = EXCLUDED.hinnang_id,
    calculated_at             = now();
    -- w1_turumaht, w3_taitumus, w4_rahaline ei uuendata — DB-s seatud väärtused säilivad

DROP VIEW IF EXISTS mart.v_piirkondade_edetabel;
CREATE VIEW mart.v_piirkondade_edetabel AS
SELECT
    ROW_NUMBER() OVER (ORDER BY s.loplik_skoor DESC) AS koht,
    m.maakond_nimi,
    ROUND(s.loplik_skoor * 100, 1)    AS skoor_pct,
    ROUND(s.turumaht_raw)             AS oobimiste_arv,
    ROUND(s.taitumus_raw, 2)          AS noudlus_pakkumine_suhe,
    ROUND(s.rahaline_potentsiaal_raw) AS rahaline_potentsiaal,
    s.turumaht_norm,
    s.taitumus_norm,
    s.rahaline_potentsiaal_norm,
    h.kategooria_nimi,
    h.soovitus,
    h.selgitus
FROM mart.fact_skoor s
JOIN mart.dim_maakond         m ON m.maakond_id = s.maakond_id
JOIN mart.dim_ariline_hinnang h ON h.hinnang_id = s.hinnang_id
ORDER BY s.loplik_skoor DESC;


/* INSERT INTO mart.dim_maakond (maakond_nimi)
SELECT DISTINCT maakond
FROM staging.raw_tu110
ORDER BY maakond
ON CONFLICT (maakond_nimi) DO NOTHING;

INSERT INTO mart.fact_oobimised (maakond, aasta, oobimiste_arv)
SELECT
    maakond,
    aasta,
    oobimiste_arv
FROM staging.raw_tu110;

INSERT INTO mart.fact_oobimised (
    maakond_id, aasta,
    majutuskohti_arv, tubade_arv, voodikohtade_arv,
    majutatute_arv, oobimiste_arv,
    tubade_taitumus_pct, voodikohtade_taitumus_pct,
    oopaeva_keskmine_maksumus
)
SELECT
    m.maakond_id,
    r.aasta,
    r.majutuskohti_arv,
    r.tubade_arv,
    r.voodikohtade_arv,
    r.majutatute_arv,
    r.oobimiste_arv,
    r.tubade_taitumus_pct,
    r.voodikohtade_taitumus_pct,
    r.oopaeva_keskmine_maksumus
FROM staging.raw_tu110 r
JOIN mart.dim_maakond m ON m.maakond_nimi = r.maakond
ON CONFLICT (maakond_id, aasta) DO UPDATE SET
    majutuskohti_arv          = EXCLUDED.majutuskohti_arv,
    tubade_arv                = EXCLUDED.tubade_arv,
    voodikohtade_arv          = EXCLUDED.voodikohtade_arv,
    majutatute_arv            = EXCLUDED.majutatute_arv,
    oobimiste_arv             = EXCLUDED.oobimiste_arv,
    tubade_taitumus_pct       = EXCLUDED.tubade_taitumus_pct,
    voodikohtade_taitumus_pct = EXCLUDED.voodikohtade_taitumus_pct,
    oopaeva_keskmine_maksumus = EXCLUDED.oopaeva_keskmine_maksumus,
    loaded_at                 = now();

-- 1. samm: viimase 4 aasta keskmised + CAGR baas + täituvus
WITH
baas AS (                                                                          
    SELECT                                                                         
        f.maakond_id,                                                              
        AVG(f.oobimiste_arv) FILTER (WHERE f.aasta >= 2022)    AS turumaht_raw,   
        MAX(f.oobimiste_arv) FILTER (WHERE f.aasta = 2025)     AS oobimine_2025,  
        MAX(f.oobimiste_arv) FILTER (WHERE f.aasta = 2022)     AS oobimine_2022,  
        MAX(f.taitumus_proxy) FILTER (WHERE f.aasta = 2025)    AS taitumus_raw,   
        MAX(f.tubade_taitumus_pct * f.oopaeva_keskmine_maksumus / 100)             
            FILTER (WHERE f.aasta = 2025)                      AS rahaline_potentsiaal_raw  
    FROM mart.fact_oobimised f                                                     
    GROUP BY f.maakond_id                                                          
),                                                                                 

-- 2. samm: CAGR arvutus
cagr_calc AS (                                                                     
    SELECT                                                                         
        maakond_id,                                                                
        turumaht_raw,                                                              
        taitumus_raw,                                                              
        rahaline_potentsiaal_raw,                                                  
        CASE                                                                       
            WHEN oobimine_2022 > 0 AND oobimine_2025 IS NOT NULL                  
            THEN POWER(oobimine_2025 / oobimine_2022, 1.0/3) - 1                  
            ELSE NULL                                                              
        END AS cagr_raw                                                            
    FROM baas                                                                      
),                                                                                 

-- 3. samm: min-max normaliseerimine üle kõigi maakondade
minmax AS (                                                                        
    SELECT                                                                         
        MIN(turumaht_raw)             AS turumaht_min,  MAX(turumaht_raw)             AS turumaht_max,  
        MIN(cagr_raw)                 AS cagr_min,      MAX(cagr_raw)                 AS cagr_max,      
        MIN(taitumus_raw)             AS taitumus_min,  MAX(taitumus_raw)             AS taitumus_max,  
        MIN(rahaline_potentsiaal_raw) AS raha_min,      MAX(rahaline_potentsiaal_raw) AS raha_max       
    FROM cagr_calc                                                                 
),                                                                                 

-- 4. samm: normaliseeritud väärtused
norm AS (                                                                          
    SELECT                                                                         
        c.maakond_id,                                                              
        c.turumaht_raw,                                                            
        c.cagr_raw,                                                                
        c.taitumus_raw,                                                            
        c.rahaline_potentsiaal_raw,                                                
        CASE WHEN m.turumaht_max > m.turumaht_min                                 
            THEN (c.turumaht_raw - m.turumaht_min) / (m.turumaht_max - m.turumaht_min)  
            ELSE 0.5 END AS turumaht_norm,                                        
        CASE WHEN m.cagr_max > m.cagr_min                                         
            THEN (c.cagr_raw - m.cagr_min) / (m.cagr_max - m.cagr_min)           
            ELSE 0.5 END AS cagr_norm,                                            
        CASE WHEN m.taitumus_max > m.taitumus_min                                 
            THEN (c.taitumus_raw - m.taitumus_min) / (m.taitumus_max - m.taitumus_min)  
            ELSE 0.5 END AS taitumus_norm,                                        
        CASE WHEN m.raha_max > m.raha_min                                         
            THEN (c.rahaline_potentsiaal_raw - m.raha_min) / (m.raha_max - m.raha_min)  
            ELSE 0.5 END AS rahaline_potentsiaal_norm                             
    FROM cagr_calc c                                                               
    CROSS JOIN minmax m                                                            
),                                                                                 

-- 5. samm: lõplik skoor
scored AS (                                                                        
    SELECT                                                                         
        *,                                                                         
        ROUND(                                                                     
            (0.25 * turumaht_norm) +                                               
            (0.35 * cagr_norm) +                                                   
            (0.25 * taitumus_norm) +                                               
            (0.15 * rahaline_potentsiaal_norm)                                     
        , 4) AS loplik_skoor                                                       
    FROM norm                                                                      
),                                                                                 

-- 6. samm: äriline hinnang (kategooria määramine skoori ja täituvuse põhjal)
hinnang AS (                                                                       
    SELECT                                                                         
        *,                                                                         
        CASE                                                                       
            WHEN loplik_skoor >= 0.65                      THEN 1  -- Atraktiivne turg   
            WHEN cagr_norm >= 0.6 AND turumaht_norm < 0.4 THEN 2  -- Kasvav turg        
            WHEN taitumus_norm < 0.35 AND cagr_norm < 0.3 THEN 3  -- Küllastunud turg   
            ELSE                                                4  -- Stabiilne rahavoog  
        END AS hinnang_id                                                          
    FROM scored                                                                    
)                                                                                  

INSERT INTO mart.fact_skoor (                    
    maakond_id,                                  
    turumaht_raw, cagr_raw, taitumus_raw, rahaline_potentsiaal_raw,  
    turumaht_norm, cagr_norm, taitumus_norm, rahaline_potentsiaal_norm,  
    loplik_skoor, hinnang_id                     
)                                                
SELECT                                           
    maakond_id,                                  
    turumaht_raw, cagr_raw, taitumus_raw, rahaline_potentsiaal_raw,  
    turumaht_norm, cagr_norm, taitumus_norm, rahaline_potentsiaal_norm,  
    loplik_skoor, hinnang_id                     
FROM hinnang                                     
ON CONFLICT (maakond_id) DO UPDATE SET           
    turumaht_raw              = EXCLUDED.turumaht_raw,              
    cagr_raw                  = EXCLUDED.cagr_raw,                  
    taitumus_raw              = EXCLUDED.taitumus_raw,              
    rahaline_potentsiaal_raw  = EXCLUDED.rahaline_potentsiaal_raw,  
    turumaht_norm             = EXCLUDED.turumaht_norm,             
    cagr_norm                 = EXCLUDED.cagr_norm,                 
    taitumus_norm             = EXCLUDED.taitumus_norm,             
    rahaline_potentsiaal_norm = EXCLUDED.rahaline_potentsiaal_norm, 
    loplik_skoor              = EXCLUDED.loplik_skoor,              
    hinnang_id                = EXCLUDED.hinnang_id,                
    calculated_at             = now();                              
 */