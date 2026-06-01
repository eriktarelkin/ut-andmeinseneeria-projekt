import os
from dotenv import load_dotenv

load_dotenv()

API_URL: str = os.getenv("API_URL", "https://andmed.stat.ee/api/v1/et/stat/TU110")