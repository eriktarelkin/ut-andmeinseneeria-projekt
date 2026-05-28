CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE IF NOT EXISTS staging.pipeline_runs (
    run_id uuid PRIMARY KEY,
    fetched_at timestamptz NOT NULL,
    source_name text NOT NULL,
    status text NOT NULL,
    message text
);

-- Üks rida = üks maakond + üks aasta kombinatsioon
CREATE TABLE IF NOT EXISTS staging.raw_tu110 (
    run_id uuid NOT NULL REFERENCES staging.pipeline_runs (run_id),
    maakond             text NOT NULL,              
    aasta               integer NOT NULL,           
    majutuskohti_arv    numeric,                    
    tubade_arv          numeric,                    
    voodikohtade_arv    numeric,                    
    tubade_taitumus_pct numeric,                    
    voodikohtade_taitumus_pct numeric,              
    oopaeva_keskmine_maksumus numeric,             
    majutatute_arv      numeric,                    
    oobimiste_arv       numeric,                   
    loaded_at           timestamp DEFAULT now(),    
    source              text DEFAULT 'stat.ee/TU110',
    PRIMARY KEY (run_id, uix_raw_tu110_maakond_aasta)
);

CREATE UNIQUE INDEX IF NOT EXISTS uix_raw_tu110_maakond_aasta
    ON staging.raw_tu110 (maakond, aasta);

CREATE TABLE IF NOT EXISTS mart.dim_maakond (
    maakond_id      serial PRIMARY KEY
    maakond_nimi    text NOT NULL UNIQUE,           
    maakond_lyhend  text,                   
    regioon         text,    
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamp DEFAULT now()
);

INSERT INTO mart.dim_maakond (maakond_nimi)
SELECT DISTINCT maakond
FROM staging.raw_tu110
ORDER BY maakond
ON CONFLICT (maakond_nimi) DO NOTHING;


-- Üks rida = üks ärikategooria
CREATE TABLE IF NOT EXISTS mart.dim_ariline_hinnang (
    hinnang_id      integer PRIMARY KEY,
    kategooria_nimi text NOT NULL,
    soovitus        text NOT NULL,
    selgitus        text NOT NULL,
    updated_at      timestamp DEFAULT now()
);

INSERT INTO mart.dim_ariline_hinnang
    (hinnang_id, kategooria_nimi, soovitus, selgitus)
VALUES
    (1, 'Atraktiivne turg',  'INVESTEERI KOHE',       'kõrge nõudlus, kõrge täituvus, tugev kasv'),
    (2, 'Kasvav turg',       'VARAJANE SISENEMINE',   'väike turg, aga kiire kasv ja potentsiaal'),
    (3, 'Küllastunud turg',  'VÄLDI',                 'täituvus madal, kasv puudub'),
    (4, 'Stabiilne rahavoog','RAHAVOO STRATEEGIA',    'stabiilne turg, vähe kasvu, aga kindel täituvus')
ON CONFLICT (hinnang_id) DO UPDATE SET
    kategooria_nimi = EXCLUDED.kategooria_nimi,
    soovitus        = EXCLUDED.soovitus,
    selgitus        = EXCLUDED.selgitus,
    updated_at      = now();

-- Üks rida = üks maakond + aasta
CREATE TABLE IF NOT EXISTS mart.fact_oobimised (
    fact_id                     serial PRIMARY KEY,
    maakond_id                  integer NOT NULL REFERENCES mart.dim_maakond(maakond_id),
    aasta                       integer NOT NULL,
    majutuskohti_arv            numeric,
    tubade_arv                  numeric,
    voodikohtade_arv            numeric,
    majutatute_arv              numeric,
    oobimiste_arv               numeric,
    tubade_taitumus_pct         numeric,
    voodikohtade_taitumus_pct   numeric,
    oopaeva_keskmine_maksumus   numeric,
    taitumus_proxy              numeric GENERATED ALWAYS AS (
        CASE WHEN tubade_arv > 0
            THEN oobimiste_arv / (tubade_arv * 365)
            ELSE NULL
        END
    ) STORED,

    loaded_at                   timestamp DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uix_fact_oobimised_maakond_aasta
    ON mart.fact_oobimised (maakond_id, aasta);

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
    majutuskohti_arv            = EXCLUDED.majutuskohti_arv,
    tubade_arv                  = EXCLUDED.tubade_arv,
    voodikohtade_arv            = EXCLUDED.voodikohtade_arv,
    majutatute_arv              = EXCLUDED.majutatute_arv,
    oobimiste_arv               = EXCLUDED.oobimiste_arv,
    tubade_taitumus_pct         = EXCLUDED.tubade_taitumus_pct,
    voodikohtade_taitumus_pct   = EXCLUDED.voodikohtade_taitumus_pct,
    oopaeva_keskmine_maksumus   = EXCLUDED.oopaeva_keskmine_maksumus,
    loaded_at                   = now();

-- Üks rida = üks maakond (viimaste andmete põhjal)
CREATE TABLE IF NOT EXISTS mart.fact_skoor (
    skoor_id                serial PRIMARY KEY,
    maakond_id              integer NOT NULL REFERENCES mart.dim_maakond(maakond_id) UNIQUE,
    turumaht_raw            numeric,    -- keskmine ööbimiste arv 2022-2025
    cagr_raw                numeric,    -- CAGR 2022→2025
    taitumus_raw            numeric,    -- täituvuse proxy (ööbimised / tubade_arv*365)
    rahaline_potentsiaal_raw numeric,   -- tubade_taitumus_pct * ööpäeva_keskmine_maksumus
    turumaht_norm           numeric,
    cagr_norm               numeric,
    taitumus_norm           numeric,
    rahaline_potentsiaal_norm numeric,
    w1_turumaht             numeric NOT NULL DEFAULT 0.25,
    w2_kasv                 numeric NOT NULL DEFAULT 0.35,
    w3_taitumus             numeric NOT NULL DEFAULT 0.25,
    w4_rahaline             numeric NOT NULL DEFAULT 0.15,
    loplik_skoor            numeric,
    hinnang_id              integer REFERENCES mart.dim_ariline_hinnang(hinnang_id),
    calculated_at           timestamp DEFAULT now()
);

WITH
-- 1. samm: viimase 4 aasta keskmised + CAGR baas + täituvus
baas AS (
    SELECT
        f.maakond_id,
        -- Turumaht: keskmine ööbimiste arv 2022-2025
        AVG(f.oobimiste_arv) FILTER (WHERE f.aasta >= 2022)    AS turumaht_raw,
        -- CAGR komponendid
        MAX(f.oobimiste_arv) FILTER (WHERE f.aasta = 2025)     AS oobimine_2025,
        MAX(f.oobimiste_arv) FILTER (WHERE f.aasta = 2022)     AS oobimine_2022,
        -- Täituvus: viimane saadaolev aasta
        MAX(f.taitumus_proxy) FILTER (WHERE f.aasta = 2025)    AS taitumus_raw,
        -- Rahaline potentsiaal: viimane aasta
        MAX(f.tubade_taitumus_pct * f.oopaeva_keskmine_maksumus / 100)
            FILTER (WHERE f.aasta = 2025)                       AS rahaline_potentsiaal_raw
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
        MIN(turumaht_raw)            AS turumaht_min,  MAX(turumaht_raw)            AS turumaht_max,
        MIN(cagr_raw)                AS cagr_min,      MAX(cagr_raw)                AS cagr_max,
        MIN(taitumus_raw)            AS taitumus_min,  MAX(taitumus_raw)            AS taitumus_max,
        MIN(rahaline_potentsiaal_raw) AS raha_min,     MAX(rahaline_potentsiaal_raw) AS raha_max
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
            WHEN loplik_skoor >= 0.65                           THEN 1  -- Atraktiivne turg
            WHEN cagr_norm >= 0.6 AND turumaht_norm < 0.4      THEN 2  -- Kasvav turg
            WHEN taitumus_norm < 0.35 AND cagr_norm < 0.3      THEN 3  -- Küllastunud turg
            ELSE                                                     4  -- Stabiilne rahavoog
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
    turumaht_raw                = EXCLUDED.turumaht_raw,
    cagr_raw                    = EXCLUDED.cagr_raw,
    taitumus_raw                = EXCLUDED.taitumus_raw,
    rahaline_potentsiaal_raw    = EXCLUDED.rahaline_potentsiaal_raw,
    turumaht_norm               = EXCLUDED.turumaht_norm,
    cagr_norm                   = EXCLUDED.cagr_norm,
    taitumus_norm               = EXCLUDED.taitumus_norm,
    rahaline_potentsiaal_norm   = EXCLUDED.rahaline_potentsiaal_norm,
    loplik_skoor                = EXCLUDED.loplik_skoor,
    hinnang_id                  = EXCLUDED.hinnang_id,
    calculated_at               = now();


-- Peamine edetabel: maakonnad parima potentsiaaliga esikohal
CREATE OR REPLACE VIEW mart.v_piirkondade_edetabel AS
SELECT
    ROW_NUMBER() OVER (ORDER BY s.loplik_skoor DESC) AS koht,
    m.maakond_nimi,
    ROUND(s.loplik_skoor * 100, 1)                  AS skoor_pct,
    ROUND(s.cagr_raw * 100, 2)                      AS kasv_cagr_pct,
    ROUND(s.taitumus_raw * 100, 1)                  AS taitumus_pct,
    ROUND(s.turumaht_raw)                           AS keskmine_oobimised,
    ROUND(s.rahaline_potentsiaal_raw, 2)            AS rahaline_potentsiaal,
    h.kategooria_nimi,
    h.soovitus,
    h.selgitus
FROM mart.fact_skoor s
JOIN mart.dim_maakond        m ON m.maakond_id  = s.maakond_id
JOIN mart.dim_ariline_hinnang h ON h.hinnang_id = s.hinnang_id
ORDER BY s.loplik_skoor DESC;


-- Aegrea vaade: kõigi aastate toorandmed maakonna kaupa
CREATE OR REPLACE VIEW mart.v_oobimised_aegrea AS
SELECT
    m.maakond_nimi,
    f.aasta,
    f.oobimiste_arv,
    f.majutatute_arv,
    f.tubade_arv,
    f.tubade_taitumus_pct,
    f.oopaeva_keskmine_maksumus,
    ROUND(f.taitumus_proxy * 100, 1) AS taitumus_proxy_pct
FROM mart.fact_oobimised f
JOIN mart.dim_maakond m ON m.maakond_id = f.maakond_id
ORDER BY m.maakond_nimi, f.aasta;