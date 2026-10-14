"""Turn composed-resource models into what the Crossplane SDK accepts."""


def to_dict(model) -> dict:
    """Serialize a composed-resource model for resource.update().

    resource.update() accepts a pydantic model directly, but dumps it without by_alias, so a
    field whose schema name isn't a valid Python identifier, such as a Python keyword, would be
    written under its Python name and rejected by the API server. It also drops fields equal to
    their defaults. Passing a dict takes resource.update()'s dict branch, which writes it as is.
    """
    return model.model_dump(by_alias=True, exclude_none=True, warnings=False)
