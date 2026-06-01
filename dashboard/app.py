import os

import altair as alt
import pandas as pd
import psycopg2
import streamlit as st

try:
    from streamlit_autorefresh import st_autorefresh
except ImportError:
    st_autorefresh = None


st.set_page_config(page_title="Majutusasutuste analüüs", layout="wide")

auto_refresh_seconds = int(os.environ.get("DASHBOARD_AUTOREFRESH_SECONDS", 30))
if auto_refresh_seconds > 0 and st_autorefresh is not None:
    st_autorefresh(interval=auto_refresh_seconds * 1000, key="dashboard_autorefresh")

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
    with get_connection() as conn:
        return pd.read_sql_query(query, conn)


def main():
    st.title("Majutusasutuste analüüs")
    st.caption("Millises Eesti piirkonnas on suurim potentsiaal avada uus majutusasutus?")

    leaderboard = load_dataframe("SELECT * FROM mart.v_piirkondade_edetabel")
    year_df     = load_dataframe("SELECT MAX(aasta) AS aasta FROM mart.fact_oobimised")
    data_year   = int(year_df["aasta"].iloc[0]) if not year_df.empty and year_df["aasta"].iloc[0] else None

    if leaderboard.empty:
        st.warning("Andmed puuduvad — käivita ingest ja 01_transform.sql.")
        return

    # Maakonna filter
    maakonnad = ["Kõik"] + sorted(leaderboard["maakond_nimi"].dropna().unique().tolist())
    valitud = st.sidebar.selectbox("Vali maakond", maakonnad)
    valitud = None if valitud == "Kõik" else valitud

    st.sidebar.markdown("---")
    st.sidebar.markdown("**Kaalud (1 aasta)**")
    st.sidebar.markdown("- Turumaht: 40%")
    st.sidebar.markdown("- Nõudlus/pakkumine: 35%")
    st.sidebar.markdown("- Rahaline potentsiaal: 25%")

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
    c4.metric("Andmete aasta", str(data_year) if data_year else "–")

    st.markdown("---")

    st.subheader("Maakondade skoorid")
    leaderboard["label"] = leaderboard["koht"].astype(str) + ". " + leaderboard["maakond_nimi"]
    bars = (
        alt.Chart(leaderboard)
        .mark_bar()
        .encode(
            x=alt.X("skoor_pct:Q", title="Koondskoor (%)", scale=alt.Scale(domain=[0, 100])),
            y=alt.Y("label:N", sort="-x", title=None,
                    scale=alt.Scale(paddingInner=0.4)),
            color=alt.Color("kategooria_nimi:N", legend=None),
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
    st.dataframe(leaderboard[veerud], use_container_width=True, hide_index=True)


if __name__ == "__main__":
    main()
