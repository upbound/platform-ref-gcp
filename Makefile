# Project Setup
PROJECT_NAME := platform-ref-gcp
PROJECT_REPO := github.com/upbound/$(PROJECT_NAME)

# NOTE(hasheddan): the platform is insignificant here as Configuration package
# images are not architecture-specific. We constrain to one platform to avoid
# needlessly pushing a multi-arch image.
PLATFORMS ?= linux_amd64
-include build/makelib/common.mk

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
-include build/makelib/controlplane.mk

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
uptest: build $(UPTEST) $(KUBECTL) $(KUTTL) local.xpkg.deploy.configuration.$(PROJECT_NAME)
	@$(INFO) running automated tests
	@KUBECTL=$(KUBECTL) KUTTL=$(KUTTL) $(UPTEST) e2e examples/cluster-claim.yaml --setup-script=test/setup.sh --default-timeout=2400 || $(FAIL)
	@$(OK) running automated tests

#TODO(turkenh): move to build submodule
CONTROLPLANE_DUMP_DIRECTORY ?= $(OUTPUT_DIR)/controlplane-dump
controlplane.dump: $(KUBECTL)
	mkdir -p $(CONTROLPLANE_DUMP_DIRECTORY)
	@$(KUBECTL) cluster-info dump --output-directory $(CONTROLPLANE_DUMP_DIRECTORY) --all-namespaces || true
	@$(KUBECTL) get managed -o yaml > $(CONTROLPLANE_DUMP_DIRECTORY)/managed.yaml || true

e2e: controlplane.up uptest