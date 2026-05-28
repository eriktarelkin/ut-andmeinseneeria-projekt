CREATE SCHEMA IF NOT EXISTS mart;

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