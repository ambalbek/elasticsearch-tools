import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from functions.config import get_config
from functions.logger import get_logger
from functions.ilm_utils import has_delete_phase, add_delete_phase
from classes.es_client import ElasticsearchClient

logger = get_logger("update_ilm_policies")


def main():
    config = get_config()
    client = ElasticsearchClient(host=config["host"], api_key=config["api_key"], verify_certs=config["verify_certs"])

    if not client.ping():
        logger.error("Cannot connect to Elasticsearch at %s", config["host"])
        sys.exit(1)

    logger.info("Connected to %s", config["host"])

    policies = client.get_all_ilm_policies()
    logger.info("Found %d ILM policies", len(policies))

    updated = 0
    skipped = 0

    for name, policy_body in policies.items():
        if has_delete_phase(policy_body):
            logger.info("SKIP  %s (delete phase already present)", name)
            skipped += 1
        else:
            new_policy = add_delete_phase(policy_body)
            client.put_ilm_policy(name, new_policy)
            logger.info("UPDATE %s (90d delete phase added)", name)
            updated += 1

    logger.info("Done. Updated: %d | Skipped: %d", updated, skipped)


if __name__ == "__main__":
    main()
