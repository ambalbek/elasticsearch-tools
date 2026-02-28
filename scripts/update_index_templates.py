import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from functions.config import get_config
from functions.logger import get_logger
from functions.template_utils import has_mapper_size, add_mapper_size
from classes.es_client import ElasticsearchClient

logger = get_logger("update_index_templates")


def main():
    config = get_config()
    client = ElasticsearchClient(host=config["host"], api_key=config["api_key"], verify_certs=config["verify_certs"])

    if not client.ping():
        logger.error("Cannot connect to Elasticsearch at %s", config["host"])
        sys.exit(1)

    logger.info("Connected to %s", config["host"])

    templates = client.get_all_index_templates()
    logger.info("Found %d index templates", len(templates))

    updated = 0
    skipped = 0

    for entry in templates:
        name = entry.get("name", "<unknown>")

        if has_mapper_size(entry):
            logger.info("SKIP  %s (mapper_size already present)", name)
            skipped += 1
        else:
            new_body = add_mapper_size(entry)
            client.put_index_template(name, new_body)
            logger.info("UPDATE %s (mapper_size added)", name)
            updated += 1

    logger.info("Done. Updated: %d | Skipped: %d", updated, skipped)


if __name__ == "__main__":
    main()
