# Project Setup
PROJECT_NAME := platform-ref-gcp
PROJECT_REPO := github.com/upbound/$(PROJECT_NAME)

# NOTE(hasheddan): the platform is insignificant here as Configuration package
# images are not architecture-specific. We constrain to one platform to avoid
# needlessly pushing a multi-arch image.
PLATFORMS ?= linux_amd64
include build/makelib/common.mk

# ====================================================================================
# Setup Kubernetes tools

UP_VERSION = v0.14.0
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

# run `make help` to see the targets and options

# We want submodules to be set up the first time `make` is run.
# We manage the build/ folder and its Makefiles as a submodule.
# The first time `make` is run, the includes of build/*.mk files will
# all fail, and this target will be run. The next time, the default as defined
# by the includes will be run instead.
fallthrough: submodules
	@echo Initial setup complete. Running make again . . .
	@make

# Update the submodules, such as the common build scripts.
submodules:
	@git submodule sync
	@git submodule update --init --recursive

# We must ensure up is installed in tool cache prior to build as including the k8s_tools machinery prior to the xpkg
# machinery sets UP to point to tool cache.
build.init: $(UP)

# ====================================================================================
# End to End Testing

KIND_VERSION = v0.16.0
KIND_CLUSTER_NAME ?= uptest
PROVIDER_GCP_VERSION ?= v0.15.0
PROVIDER_HELM_VERSION ?= v0.12.0

controlplane.up: $(UP) $(KUBECTL) $(KIND)
	@$(INFO) setting up controlplane
	@$(KIND) get kubeconfig --name $(KIND_CLUSTER_NAME) >/dev/null 2>&1 || $(KIND) create cluster --name=$(KIND_CLUSTER_NAME)
	@$(KUBECTL) -n upbound-system get cm universal-crossplane-config >/dev/null 2>&1 || $(UP) uxp install
	@$(KUBECTL) -n upbound-system wait deploy crossplane --for condition=Available --timeout=120s
	@$(KUBECTL) get provider.pkg upbound-provider-gcp > /dev/null 2>&1 || $(UP) ctp provider install upbound/provider-gcp:$(PROVIDER_GCP_VERSION)
	@$(KUBECTL) get provider.pkg crossplane-contrib-provider-helm > /dev/null 2>&1 || $(UP) ctp provider install crossplane-contrib/provider-helm:$(PROVIDER_HELM_VERSION)
	@$(KUBECTL) wait provider.pkg upbound-provider-gcp --for condition=Healthy --timeout=120s
	@$(KUBECTL) wait provider.pkg crossplane-contrib-provider-helm --for condition=Healthy --timeout=120s
	@$(OK) setting up controlplane

controlplane.down: $(UP) $(KUBECTL) $(KIND)
	@$(INFO) deleting controlplane
	@$(KIND) get kubeconfig --name $(KIND_CLUSTER_NAME) >/dev/null 2>&1 && $(KIND) delete cluster --name=$(KIND_CLUSTER_NAME)
	@$(OK) deleting controlplane

uptest-local: $(UP) $(KUBECTL) $(KUTTL)
	@$(INFO) running automated tests
	@$(KUBECTL) apply -R -f package/cluster
	@KUBECTL=$(KUBECTL) KUTTL=$(KUTTL) uptest e2e examples/cluster-claim.yaml --setup-script=test/setup.sh --default-timeout=2400 || $(FAIL)
	@$(OK) running automated tests

e2e: controlplane.up uptest-local
