# Cluster composition function

Composes a `Cluster` from the domain APIs it builds on: `Network`, `GKE`, `Oss`
and `Flux`, plus the `Usage`s that keep the GKE cluster until everything running
on it is gone.

The function composes domain resources only, never provider managed resources,
and makes the implementation choices the `Cluster` API leaves open: the machine
type for each node size and the default operator chart versions. See
[Changing the platform](../../README.md#changing-the-platform) before editing
them or the composition resource names.

[function/core.py](function/core.py) builds the composed resources and status
without talking to Crossplane; [function/fn.py](function/fn.py) only handles the
request and serializes with [function/serialize.py](function/serialize.py).

```console
up project build                          # generates the models into .up/python
python -m pytest tests -q                 # unit tests, from this directory
up test run tests/test-cluster            # composition tests, from the repository root
```
