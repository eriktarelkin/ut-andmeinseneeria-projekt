CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS quality;

CREATE TABLE IF NOT EXISTS quality.test_results (
    id          serial PRIMARY KEY,
    test_name   text        NOT NULL,
    status      text        NOT NULL CHECK (status IN ('passed', 'failed')),
    failed_rows integer     NOT NULL,
    message     text        NOT NULL,
    run_at      timestamptz NOT NULL DEFAULT now()
);

-- Üks rida — järgmine aasta, mida pärida (tsükliline kursor)
CREATE TABLE IF NOT EXISTS staging.ingest_cursor (
    id         int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    next_year  int NOT NULL,
    updated_at timestamptz DEFAULT now()
);

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
    CASE WHEN voodikohtade_arv > 0
        THEN oobimiste_arv / (voodikohtade_arv * 365)
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
    w1_turumaht               numeric NOT NULL DEFAULT 0.40,
    w2_kasv                   numeric NOT NULL DEFAULT 0.35,
    w3_taitumus               numeric NOT NULL DEFAULT 0.35,
    w4_rahaline               numeric NOT NULL DEFAULT 0.25,
    loplik_skoor              numeric,
    hinnang_id                integer REFERENCES mart.dim_ariline_hinnang (hinnang_id),
    calculated_at             timestamp DEFAULT now()
);

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