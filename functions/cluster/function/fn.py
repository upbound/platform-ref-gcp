"""Composition function for the platform-ref-gcp Cluster.

The composition logic lives in core.py; this module only talks to Crossplane.
"""

import grpc
from crossplane.function import logging, resource, response
from crossplane.function.proto.v1 import run_function_pb2 as fnv1
from crossplane.function.proto.v1 import run_function_pb2_grpc as grpcv1
from models.io.upbound.platformref.gcp.cluster import v1alpha1 as clusterv1alpha1
from pydantic import ValidationError

from . import core
from .serialize import to_dict

# The required-resources key the Apps arrive under.
APPS = "apps"


class FunctionRunner(grpcv1.FunctionRunnerService):
    """A FunctionRunner handles gRPC RunFunctionRequests."""

    def __init__(self):
        """Create a new FunctionRunner."""
        self.log = logging.get_logger()

    async def RunFunction(
        self, req: fnv1.RunFunctionRequest, _: grpc.aio.ServicerContext
    ) -> fnv1.RunFunctionResponse:
        """Run the function."""
        log = self.log.bind(tag=req.meta.tag)
        rsp = response.to(req)

        try:
            xr = clusterv1alpha1.Cluster(**resource.struct_to_dict(req.observed.composite.resource))
        except ValidationError as e:
            response.fatal(rsp, f"invalid Cluster: {e}")
            return rsp

        # Ask for the Apps on every call; Crossplane supplies them on the next one.
        response.require_resources(
            rsp,
            APPS,
            core.APP_API_VERSION,
            "App",
            match_labels={core.DELETION_ORDERING_LABEL: "enabled"},
            namespace=xr.metadata.namespace,
        )
        apps = [resource.struct_to_dict(a.resource) for a in req.required_resources[APPS].items]

        observed = {
            name: resource.struct_to_dict(r.resource) for name, r in req.observed.resources.items()
        }

        params = xr.spec.parameters
        resources = core.build(xr.metadata.name, params, observed=observed, apps=apps)
        for name, model in resources.items():
            resource.update(rsp.desired.resources[name], to_dict(model))
        resource.update(rsp.desired.composite, {"status": core.status(params, observed=observed)})

        log.info("Composed resources", count=len(resources))
        return rsp
