import os

import firebase_admin
from firebase_admin import credentials, db, firestore

from env_config import get_database_url, get_service_account_path


def initialize_firebase():
    if not firebase_admin._apps:
        cred_path = get_service_account_path()
        if not os.path.isfile(cred_path):
            raise FileNotFoundError(
                f"Firebase service account file not found: {cred_path}. "
                "Download it from Firebase Console and set FIREBASE_SERVICE_ACCOUNT_PATH in .env"
            )

        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(
            cred,
            {"databaseURL": get_database_url()},
        )
    return firestore.client(), db.reference()
