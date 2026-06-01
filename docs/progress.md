# Edenemisraport

## Mis on valmis

- [x] Docker Compose käivitab kõik teenused
- [x] Andmeid saadakse allikast kätte
- [x] Andmed laetakse `staging` kihti
- [x] Vähemalt üks transformatsioon toimib
- [x] Vähemalt üks näidikulaud on nähtaval
- [ ] Vähemalt üks andmekvaliteedi test läbib

Andmevoog töötab otsast lõpuni: Statistikaameti TU110 API → `staging.raw_tu110` → `mart.fact_skoor` → Streamlit näidikulaud. Pipeline käivitub automaatselt konteinerite käivitamisel.

## Järgmised sammud

- Lisada CAGR mõõdik, kui mitme-aastased andmed on kontrollitud
- Kirjutada andmekvaliteedi testid (`02_quality_tests.sql`)
- Täiendada README juhendiga uue kasutaja jaoks

## Mis takistab

Praegu pole blokeerivaid probleeme.

## Kontrollpunkt

```bash
docker compose up -d --build
# Oota ~30 sekundit, seejärel:
docker compose exec pipeline python scripts/run_pipeline.py check
```

Oodatav tulemus: tabelis "Top 5 piirkonda" on maakonnad skooriga vahemikus 0–100 ja soovitusega (nt `INVESTEERI KOHE`). Näidikulaud on nähtav aadressil `http://localhost:8501`.
