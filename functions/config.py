import os
from dotenv import load_dotenv


def get_config() -> dict:
    load_dotenv()

    host = os.getenv("ES_HOST")
    api_key = os.getenv("ES_API_KEY")

    missing = [name for name, val in [("ES_HOST", host), ("ES_API_KEY", api_key)] if not val]
    if missing:
        raise EnvironmentError(f"Missing required environment variables: {', '.join(missing)}")

    verify_certs_raw = os.getenv("ES_VERIFY_CERTS", "true").strip().lower()
    verify_certs = verify_certs_raw not in ("false", "0", "no")

    return {"host": host, "api_key": api_key, "verify_certs": verify_certs}
