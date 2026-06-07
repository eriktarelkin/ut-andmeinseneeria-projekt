# Edenemisraport

## Mis on valmis

- [x] Docker Compose käivitab kõik teenused
- [x] Andmeid saadakse allikast kätte
- [x] Andmed laetakse `staging` kihti
- [x] Inkrementaalne laadimine (`staging.ingest_cursor`)
- [x] Pipeline auditijälg (`staging.pipeline_runs`)
- [x] Vähemalt üks transformatsioon toimib
- [x] CAGR mõõdik on implementeeritud (3-aastane liitkasvumäär)
- [x] Kõik neli mõõdikut koos kaaludega (turumaht 40%, CAGR 35%, täituvus 35%, rahaline potentsiaal 25%)
- [x] Ärikategooriad ja soovitused (4 kategooriat)
- [x] Vähemalt üks näidikulaud on nähtaval
- [x] Andmekvaliteedi testid — 12 automaattesti (`02_quality.sql`)

Andmevoog töötab otsast lõpuni: Statistikaameti TU110 API → `staging.raw_tu110` → `mart.fact_skoor` → Streamlit näidikulaud. Pipeline käivitub automaatselt konteinerite käivitamisel.

## Kontrollpunkt

```bash
docker compose up -d --build
# Oota ~30 sekundit, seejärel:
docker compose exec pipeline python scripts/run_pipeline.py check
```

Oodatav tulemus: tabelis "Top 5 piirkonda" on maakonnad skooriga vahemikus 0–100 ja soovitusega (nt `INVESTEERI KOHE`). Näidikulaud on nähtav aadressil `http://localhost:8501`. Kvaliteeditestide staatus on nähtav külgribal (10/10 läbitud).

## Teadaolevad piirangud

- Statistikamet uuendab TU110 andmeid kord aastas — CAGR arvutused vajavad piisavalt ajaloolisi aastaid (vähemalt 4).
- Automaatsed teavitused kvaliteeditestide ebaõnnestumisest puuduvad (tulemused on logitud, kuid teavitust ei saadeta).
