import os
import time
import altair as alt
import pandas as pd
import psycopg2
import streamlit as st

try:
    from streamlit_autorefresh import st_autorefresh
except ImportError:
    st_autorefresh = None

st.set_page_config(page_title="Majutusasutuste analüüs", layout="wide")

auto_refresh_seconds = int(os.environ.get("DASHBOARD_AUTOREFRESH_SECONDS", 5))

if st.sidebar.button("Värskenda vaade"):
    st.rerun()


def get_connection():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "db"),
        port=os.environ.get("DB_PORT", "5432"),
        user=os.environ.get("DB_USER", "praktikum"),
        password=os.environ.get("DB_PASSWORD", "praktikum"),
        dbname=os.environ.get("DB_NAME", "praktikum"),
    )

def load_dataframe(query: str) -> pd.DataFrame:
    try:
        with get_connection() as conn:
            return pd.read_sql_query(query, conn)
    except Exception:
        return pd.DataFrame()

def main():
    st.title("Majutusasutuste analüüs")
    st.caption("Millises Eesti piirkonnas on suurim potentsiaal avada uus majutusasutus?")

    leaderboard = load_dataframe("SELECT * FROM mart.v_piirkondade_edetabel")
    years_df    = load_dataframe("SELECT MIN(aasta) AS min_aasta, MAX(aasta) AS max_aasta FROM mart.fact_oobimised")
    quality_df  = load_dataframe("SELECT status, COUNT(*) AS n FROM quality.test_results GROUP BY status")

    if leaderboard.empty:
        st.warning("Andmed puuduvad — käivita pipeline.")
        return

    min_aasta = int(years_df["min_aasta"].iloc[0]) if not years_df.empty and years_df["min_aasta"].iloc[0] else None
    max_aasta = int(years_df["max_aasta"].iloc[0]) if not years_df.empty and years_df["max_aasta"].iloc[0] else None
    aasta_vahemik = f"{min_aasta}–{max_aasta}" if min_aasta and max_aasta else "–"

    passed = int(quality_df.loc[quality_df["status"] == "passed", "n"].sum()) if not quality_df.empty else 0
    failed = int(quality_df.loc[quality_df["status"] == "failed", "n"].sum()) if not quality_df.empty else 0
    total  = passed + failed

    # Piirkonna filter
    piirkonnad = ["Kõik"] + sorted(leaderboard["maakond_nimi"].dropna().unique().tolist())
    valitud = st.sidebar.selectbox("Vali piirkond", piirkonnad)
    valitud = None if valitud == "Kõik" else valitud
    if valitud:
        leaderboard = leaderboard[leaderboard["maakond_nimi"] == valitud]

    st.sidebar.markdown("---")
    if failed > 0:
        st.sidebar.error(f"Kvaliteet: {failed}/{total} testi ebaõnnestus")
    elif total > 0:
        st.sidebar.success(f"Kvaliteet: {passed}/{total} testi OK")

    # Parim piirkond
    top = leaderboard.iloc[0]
    st.success(
        f"**Parim investeerimisvõimalus: {top['maakond_nimi']}**  \n"
        f"Soovitus: **{top['soovitus']}**  \n"
        f"{top['selgitus']}  \n"
        f"Koondskoor: **{top['skoor_pct']}%**"
    )

    # KPI-d
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Piirkondi kokku", len(leaderboard))
    c2.metric("Parim piirkond", top["maakond_nimi"])
    c3.metric("Kõrgeim skoor", f"{top['skoor_pct']}%")
    c4.metric("Andmete aastad", aasta_vahemik)

    st.markdown("---")

    st.subheader("Piirkondade skoorid")
    leaderboard["label"] = leaderboard["koht"].astype(str) + ". " + leaderboard["maakond_nimi"]
    bars = (
        alt.Chart(leaderboard)
        .mark_bar()
        .encode(
            x=alt.X("skoor_pct:Q", title="Koondskoor (%)", scale=alt.Scale(domain=[0, 100])),
            y=alt.Y("label:N", sort="-x", title=None,
                    scale=alt.Scale(paddingInner=0.4)),
            color=alt.Color("kategooria_nimi:N", legend=alt.Legend(title="Kategooria")),
            tooltip=["maakond_nimi:N", "skoor_pct:Q", "soovitus:N"],
        )
        .properties(height=600)
    )
    st.altair_chart(bars, use_container_width=True)

    st.markdown("---")

    st.subheader("Detailne edetabel")
    veerud = [c for c in ["koht", "maakond_nimi", "skoor_pct", "oobimiste_arv",
                           "noudlus_pakkumine_suhe", "rahaline_potentsiaal",
                           "kategooria_nimi", "soovitus"] if c in leaderboard.columns]
    st.dataframe(
        leaderboard[veerud].rename(columns={
            "maakond_nimi":          "Piirkond",
            "skoor_pct":             "Koondskoor (%)",
            "oobimiste_arv":         "Ööbimisi aastas",
            "noudlus_pakkumine_suhe": "Täituvus",
            "rahaline_potentsiaal":  "Hinnanguline käive (€)",
            "kategooria_nimi":       "Kategooria",
            "soovitus":              "Soovitus",
        }),
        use_container_width=True,
        hide_index=True,
    )

    time.sleep(auto_refresh_seconds)
    st.rerun()

#if __name__ == "__main__":
main()
