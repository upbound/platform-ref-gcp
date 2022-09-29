# Project Setup
PROJECT_NAME := platform-ref-gcp
PROJECT_REPO := github.com/upbound/$(PROJECT_NAME)

PLATFORMS ?= linux_amd64 linux_arm64
include build/makelib/common.mk

# ====================================================================================
# Setup Kubernetes tools

UP_VERSION = v0.13.0
UP_CHANNEL = stable

-include build/makelib/k8s_tools.mk
# ====================================================================================
# Setup XPKG

XPKG_REG_ORGS ?= xpkg.upbound.io/upbound
# NOTE(hasheddan): skip promoting on xpkg.upbound.io as channel tags are
# inferred.
XPKG_REG_ORGS_NO_PROMOTE ?= xpkg.upbound.io/upbound
XPKGS = $(PROJECT_NAME)
-include build/makelib/xpkg.mk

CROSSPLANE_NAMESPACE = upbound-system
-include build/makelib/local.xpkg.mk

# ====================================================================================
# Targets

# NOTE(hasheddan): we must ensure up is installed in tool cache prior to build
# as including the k8s_tools machinery prior to the xpkg machinery sets UP to
# point to tool cache.
build.init: $(UP)

KIND_CLUSTER_NAME ?= local-dev

cluster.uxp: $(KIND) $(KUBECTL)
	@$(INFO) Setting up UXP cluster
	@$(KIND) get kubeconfig --name $(KIND_CLUSTER_NAME) >/dev/null 2>&1 || $(KIND) create cluster --name=$(KIND_CLUSTER_NAME)
	@$(KUBECTL) -n upbound-system get cm universal-crossplane-config >/dev/null 2>&1 || $(UP) uxp install
	@$(KUBECTL) -n upbound-system wait deploy crossplane --for condition=Available --timeout=60s
	@$(OK) Setting up UXP cluster

cluster.mcp: $(UP)
	@$(INFO) Setting up MCP cluster
	# NOTE(turkenh): Tried using kuttl with MCP but it is not working due to lack of permissions.
	# It either tries to create a namespace or checks for a serviceaccount in the default namespace which is not
	# allowed today. Other than that, there were also some glitches with using up to create and connect to an MCP
	# basically around providing a valid token to get kubeconfig command which need to be improved if we want to
	# MCP for testing.
	@$(ERR) Setting up MCP cluster

package-pull-secret: $(UP)
	@$(INFO) Confuguring package pull secret for Upbound Marketplace
	@$(UP) login -u $(UPBOUND_USERNAME) -p $(UPBOUND_PASSWORD)
	@$(UP) ctp pull-secret create package-pull-secret
	@$(KUBECTL) patch serviceaccount crossplane -n upbound-system -p '{"imagePullSecrets": [{"name": "package-pull-secret"}]}'
	@$(OK) Confuguring package pull secret for Upbound Marketplace

deploy-configuration: $(KUBECTL)
	@$(INFO) Applying Compositions 
	@${KUBECTL} apply -f tests/cluster/providers.yaml
	@${KUBECTL} apply -R -f package/cluster
	@$(OK) Applying Configuration

test.integration: $(KUTTL) deploy-configuration # local.xpkg.deploy.platform-ref-gcp
	@$(INFO) Running integration tests
	@$(KUBECTL) -n upbound-system create secret generic gcp-creds --from-literal=key="$${GCP_CREDS}" --dry-run=client -o yaml | $(KUBECTL) apply -f -
	@KUBECTL=$(KUBECTL) $(KUTTL) test tests --start-kind=false --skip-cluster-delete --report xml --artifacts-dir results 2>&1
	@$(OK) Ran integration tests

test.cleanup:
	@$(KIND) delete cluster --name=$(KIND_CLUSTER_NAME)

e2e.init: cluster.uxp package-pull-secret
e2e.run: test.integration
