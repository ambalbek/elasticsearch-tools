import copy


def has_mapper_size(template_entry: dict) -> bool:
    composed_of = template_entry.get("index_template", {}).get("composed_of", [])
    return "mapper_size" in composed_of


def add_mapper_size(template_entry: dict) -> dict:
    body = copy.deepcopy(template_entry.get("index_template", {}))
    composed_of = body.get("composed_of", [])
    composed_of.append("mapper_size")
    body["composed_of"] = composed_of
    return body
