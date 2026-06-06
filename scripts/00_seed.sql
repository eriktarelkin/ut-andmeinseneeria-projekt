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

CREATE TABLE IF NOT EXISTS staging.ingest_cursor (
    id         int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    next_year  int NOT NULL,
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mart.dim_ariline_hinnang (
    hinnang_id      integer PRIMARY KEY,
    kategooria_nimi text NOT NULL,
    soovitus        text NOT NULL,
    selgitus        text NOT NULL,
    updated_at      timestamp DEFAULT now()
);

ALTER TABLE mart.dim_ariline_hinnang
    ADD COLUMN IF NOT EXISTS updated_at timestamp DEFAULT now();

DROP TABLE IF EXISTS tmp_seed_ariline_hinnang;

CREATE TEMP TABLE tmp_seed_ariline_hinnang (
    hinnang_id      integer PRIMARY KEY,
    kategooria_nimi text NOT NULL,
    soovitus        text NOT NULL,
    selgitus        text NOT NULL,
    updated_at      timestamp DEFAULT now()
) ON COMMIT DROP;

INSERT INTO tmp_seed_ariline_hinnang (
    hinnang_id,
    kategooria_nimi,
    soovitus,
    selgitus
)
VALUES
    (1, 'Atraktiivne turg',   'INVESTEERI KOHE',      'kõrge nõudlus, kõrge täituvus, tugev kasv'),
    (2, 'Kasvav turg',        'VARAJANE SISENEMINE',  'väike turg, aga kiire kasv ja potentsiaal'),
    (3, 'Küllastunud turg',   'VÄLDI',                'täituvus madal, kasv puudub'),
    (4, 'Stabiilne rahavoog', 'RAHAVOO STRATEEGIA',   'stabiilne turg, vähe kasvu, aga kindel täituvus')
ON CONFLICT (hinnang_id) DO UPDATE SET
    kategooria_nimi = EXCLUDED.kategooria_nimi,
    soovitus        = EXCLUDED.soovitus,
    selgitus        = EXCLUDED.selgitus,
    updated_at      = now();

DROP TABLE IF EXISTS tmp_seed_maakond;

CREATE TEMP TABLE tmp_seed_maakond (
    maakond_nimi   text NOT NULL,
    maakond_lyhend text,
    regioon        text
) ON COMMIT DROP;

INSERT INTO tmp_seed_maakond (maakond_nimi, maakond_lyhend, regioon)
VALUES
    ('Harju maakond',      'HA',  'Põhja-Eesti'),
    ('Hiiu maakond',       'HI',  'Lääne-Eesti'),
    ('Ida-Viru maakond',   'IV',  'Kirde-Eesti'),
    ('Jõgeva maakond',     'JÕ',  'Lõuna-Eesti'),
    ('Järva maakond',      'JÄ',  'Kesk-Eesti'),
    ('Lääne maakond',      'LÄ',  'Lääne-Eesti'),
    ('Lääne-Viru maakond', 'LV',  'Kesk-Eesti'),
    ('Põlva maakond',      'PÕ',  'Lõuna-Eesti'),
    ('Pärnu maakond',      'PÄ',  'Lääne-Eesti'),
    ('Rapla maakond',      'RA',  'Kesk-Eesti'),
    ('Saare maakond',      'SA',  'Lääne-Eesti'),
    ('Tartu maakond',      'TA',  'Lõuna-Eesti'),
    ('Valga maakond',      'VA',  'Lõuna-Eesti'),
    ('Viljandi maakond',   'VI',  'Lõuna-Eesti'),
    ('Võru maakond',       'VÕ',  'Lõuna-Eesti'),
    ('Tallinn',            'TLN', 'Põhja-Eesti'),
    ('Narva linn',         'NRV', 'Kirde-Eesti'),
    ('Pärnu linn',         'PÄR', 'Lääne-Eesti'),
    ('Tartu linn',         'TRT', 'Lõuna-Eesti');

INSERT INTO mart.dim_maakond (maakond_nimi, maakond_lyhend, regioon)
SELECT maakond_nimi, maakond_lyhend, regioon
FROM tmp_seed_maakond
ON CONFLICT (maakond_nimi) DO UPDATE SET
    maakond_lyhend = COALESCE(mart.dim_maakond.maakond_lyhend, EXCLUDED.maakond_lyhend),
    regioon        = COALESCE(mart.dim_maakond.regioon,        EXCLUDED.regioon);

INSERT INTO mart.dim_ariline_hinnang (
    hinnang_id,
    kategooria_nimi,
    soovitus,
    selgitus
)
SELECT
    hinnang_id,
    kategooria_nimi,
    soovitus,
    selgitus
FROM tmp_seed_ariline_hinnang
ON CONFLICT (hinnang_id) DO UPDATE SET
    kategooria_nimi = EXCLUDED.kategooria_nimi,
    soovitus        = EXCLUDED.soovitus,
    selgitus        = EXCLUDED.selgitus,
    updated_at      = now();