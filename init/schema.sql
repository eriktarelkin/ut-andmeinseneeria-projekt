CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE IF NOT EXISTS staging.pipeline_runs (
    run_id      uuid PRIMARY KEY,
    fetched_at  timestamptz NOT NULL,
    source_name text NOT NULL,
    status      text NOT NULL,
    message     text
);

-- Üks rida = üks maakond + üks aasta kombinatsioon
CREATE TABLE IF NOT EXISTS staging.raw_tu110 (
    run_id                    uuid NOT NULL REFERENCES staging.pipeline_runs (run_id),
    maakond                   text NOT NULL,
    aasta                     integer NOT NULL,
    majutuskohti_arv          numeric,
    tubade_arv                numeric,
    voodikohtade_arv          numeric,
    tubade_taitumus_pct       numeric,
    voodikohtade_taitumus_pct numeric,
    oopaeva_keskmine_maksumus numeric,
    majutatute_arv            numeric,
    oobimiste_arv             numeric,
    loaded_at                 timestamp DEFAULT now(),
    source                    text DEFAULT 'stat.ee/TU110',
    PRIMARY KEY (maakond, aasta)
);

CREATE TABLE IF NOT EXISTS mart.dim_maakond (
    maakond_id     serial PRIMARY KEY,
    maakond_nimi   text NOT NULL UNIQUE,
    maakond_lyhend text,
    regioon        text,
    is_active      boolean NOT NULL DEFAULT true,
    created_at     timestamp DEFAULT now()
);

-- Üks rida = üks ärikategooria
CREATE TABLE IF NOT EXISTS mart.dim_ariline_hinnang (
    hinnang_id      integer PRIMARY KEY,
    kategooria_nimi text NOT NULL,
    soovitus        text NOT NULL,
    selgitus        text NOT NULL,
    updated_at      timestamp DEFAULT now()
);

-- Üks rida = üks maakond + aasta
CREATE TABLE IF NOT EXISTS mart.fact_oobimised (
    fact_id                   serial PRIMARY KEY,
    maakond_id                integer NOT NULL REFERENCES mart.dim_maakond (maakond_id),
    aasta                     integer NOT NULL,
    majutuskohti_arv          numeric,
    tubade_arv                numeric,
    voodikohtade_arv          numeric,
    majutatute_arv            numeric,
    oobimiste_arv             numeric,
    tubade_taitumus_pct       numeric,
    voodikohtade_taitumus_pct numeric,
    oopaeva_keskmine_maksumus numeric,
    taitumus_proxy            numeric GENERATED ALWAYS AS (
        CASE WHEN tubade_arv > 0
            THEN oobimiste_arv / (tubade_arv * 365)
            ELSE NULL
        END
    ) STORED,
    loaded_at                 timestamp DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uix_fact_oobimised_maakond_aasta
    ON mart.fact_oobimised (maakond_id, aasta);

-- Üks rida = üks maakond (viimaste andmete põhjal)
CREATE TABLE IF NOT EXISTS mart.fact_skoor (
    skoor_id                  serial PRIMARY KEY,
    maakond_id                integer NOT NULL REFERENCES mart.dim_maakond (maakond_id) UNIQUE,
    turumaht_raw              numeric,
    cagr_raw                  numeric,
    taitumus_raw              numeric,
    rahaline_potentsiaal_raw  numeric,
    turumaht_norm             numeric,
    cagr_norm                 numeric,
    taitumus_norm             numeric,
    rahaline_potentsiaal_norm numeric,
    w1_turumaht               numeric NOT NULL DEFAULT 0.25,
    w2_kasv                   numeric NOT NULL DEFAULT 0.35,
    w3_taitumus               numeric NOT NULL DEFAULT 0.25,
    w4_rahaline               numeric NOT NULL DEFAULT 0.15,
    loplik_skoor              numeric,
    hinnang_id                integer REFERENCES mart.dim_ariline_hinnang (hinnang_id),
    calculated_at             timestamp DEFAULT now()
);

CREATE OR REPLACE VIEW mart.v_piirkondade_edetabel AS
SELECT
    ROW_NUMBER() OVER (ORDER BY s.loplik_skoor DESC) AS koht,
    m.maakond_nimi,
    ROUND(s.loplik_skoor * 100, 1)                   AS skoor_pct,
    ROUND(s.cagr_raw * 100, 2)                       AS kasv_cagr_pct,
    ROUND(s.taitumus_raw * 100, 1)                   AS taitumus_pct,
    ROUND(s.turumaht_raw)                            AS keskmine_oobimised,
    ROUND(s.rahaline_potentsiaal_raw, 2)             AS rahaline_potentsiaal,
    h.kategooria_nimi,
    h.soovitus,
    h.selgitus
FROM mart.fact_skoor s
JOIN mart.dim_maakond         m ON m.maakond_id = s.maakond_id
JOIN mart.dim_ariline_hinnang h ON h.hinnang_id = s.hinnang_id
ORDER BY s.loplik_skoor DESC;

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