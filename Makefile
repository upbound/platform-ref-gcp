# Project Setup
PROJECT_NAME := platform-ref-gcp
PROJECT_REPO := github.com/upbound/$(PROJECT_NAME)

# NOTE(turkenh): we need to publish only for linux_amd64 because we are using
# pkg controllers seems to be looking for that explicitly. Otherwise, it was failing with: 
# cannot initialize parser backend: failed to fetch package from remote: no child with 
# platform linux/amd64 in index xpkg.upbound.io/upbound/platform-ref-gcp:v0.2.0-rc.0.4.gdac9a0c
PLATFORMS ?= linux_amd64
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