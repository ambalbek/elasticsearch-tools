import copy


def has_delete_phase(policy_body: dict) -> bool:
    phases = policy_body.get("policy", {}).get("phases", {})
    return "delete" in phases


def add_delete_phase(policy_body: dict) -> dict:
    body = copy.deepcopy(policy_body)
    phases = body.setdefault("policy", {}).setdefault("phases", {})
    phases["delete"] = {
        "min_age": "90d",
        "actions": {
            "delete": {}
        }
    }
    return body
