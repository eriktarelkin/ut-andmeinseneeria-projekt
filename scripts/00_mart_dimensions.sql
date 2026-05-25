CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE IF NOT EXISTS mart.dim_hinnang_piirkonnale (
    hinnangu_id text PRIMARY KEY,
    '''location_name text NOT NULL, # näidis
    country text NOT NULL,
    county text NOT NULL,
    location_type text NOT NULL,
    latitude numeric(9, 4) NOT NULL,
    longitude numeric(9, 4) NOT NULL,
    display_order integer NOT NULL,
    is_active boolean NOT NULL DEFAULT true'''
);

'meie tabel

kategooria_id	kategooria_nimi	soovitus	selgitus
1	Atraktiivne turg	INVESTEERI KOHE	kõrge nõudlus, pakkumise vajadus ja kasv
2	Kasvav turg	VARAJANE SISENEMINE	väike turg, aga kiire kasv ja potentsiaal
3	Küllastunud turg	VÄLDI	pakkumine ületab nõudlust, kasv puudub
4	Stabiilne rahavoog	RAHAVOO STRATEEGIA	stabiilne turg, vähe kasvu, aga kindel täituvus'