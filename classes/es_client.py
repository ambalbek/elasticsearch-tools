from elasticsearch import Elasticsearch


class ElasticsearchClient:
    def __init__(self, host: str, api_key: str, verify_certs: bool = True):
        self._client = Elasticsearch(
            hosts=[host],
            api_key=api_key,
            verify_certs=verify_certs,
            ssl_show_warn=False,
        )

    def ping(self) -> bool:
        return self._client.ping()

    def get_all_index_templates(self) -> list[dict]:
        response = self._client.indices.get_index_template()
        return response.get("index_templates", [])

    def put_index_template(self, name: str, body: dict) -> None:
        self._client.indices.put_index_template(name=name, body=body)

    def get_all_ilm_policies(self) -> dict:
        return dict(self._client.ilm.get_lifecycle())

    def put_ilm_policy(self, name: str, policy: dict) -> None:
        self._client.ilm.put_lifecycle(name=name, body=policy)
