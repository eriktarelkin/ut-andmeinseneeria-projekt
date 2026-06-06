FROM python:3.13-slim

WORKDIR /app

RUN pip install --no-cache-dir \
    streamlit \
    pandas \
    altair \
    psycopg2-binary \
    requests \
    streamlit-autorefresh

COPY . /app

EXPOSE 8501

CMD ["streamlit", "run", "app.py", "--server.address=0.0.0.0", "--server.port=8501"]