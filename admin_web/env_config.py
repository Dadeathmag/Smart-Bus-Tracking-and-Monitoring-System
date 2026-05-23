import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")


def get_service_account_path() -> str:
    path = os.environ.get("FIREBASE_SERVICE_ACCOUNT_PATH", "serviceKey.json")
    if not os.path.isabs(path):
        path = str(Path(__file__).resolve().parent / path)
    return path


def get_database_url() -> str:
    url = os.environ.get("FIREBASE_DATABASE_URL")
    if not url:
        raise RuntimeError(
            "FIREBASE_DATABASE_URL is not set. Copy .env.example to .env and configure it."
        )
    return url


def get_firebase_client_config() -> dict:
    mapping = {
        "apiKey": "FIREBASE_API_KEY",
        "authDomain": "FIREBASE_AUTH_DOMAIN",
        "projectId": "FIREBASE_PROJECT_ID",
        "appId": "FIREBASE_APP_ID",
    }
    config = {}
    missing = []
    for key, env_name in mapping.items():
        value = os.environ.get(env_name)
        if not value:
            missing.append(env_name)
        else:
            config[key] = value
    if missing:
        raise RuntimeError(
            "Missing Firebase client env vars: "
            + ", ".join(missing)
            + ". Copy .env.example to .env and configure them."
        )
    return config
