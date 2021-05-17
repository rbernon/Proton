#See help target below for documentation

ifeq ($(build_name),)
    _build_name := $(shell git symbolic-ref --short HEAD 2>/dev/null)-local
else
    _build_name := $(build_name)
endif

ifeq ($(_build_name),)
    $(error ERROR: Unable to auto-detect build name. Check out a branch or specify with "build_name=...")
endif

# remove special chars
override _build_name := $(shell echo $(_build_name) | tr -dc '[:alnum:] ._-')

# make doesn't handle spaces well... replace them with underscores in paths
BUILD_DIR := "build-$(shell echo $(_build_name) | sed -e 's/ /_/g')"
STEAM_DIR := $(HOME)/.steam/root

ifeq ($(build_name),)
    DEPLOY_DIR := $(shell git describe --tags --always)
else
    DEPLOY_DIR := $(_build_name)
endif

enable_ccache := 1
ifneq ($(enable_ccache),0)
    CCACHE_FLAG := ENABLE_CCACHE=1
endif

ifneq ($(module),)
    ifneq ($(findstring .,$(module)),)
		MODULE_SFX :=
	else
		MODULE_SFX := .dll
	endif
endif

ifneq ($(unstripped),)
    UNSTRIPPED := UNSTRIPPED_BUILD=1
    DEPLOY_DIR := $(DEPLOY_DIR)_unstripped
endif

CONFIGURE_CMD := ../proton/configure.sh \
	--build-name="$(_build_name)"

ifneq ($(protonsdk_version),)
CONFIGURE_CMD += --proton-sdk-image=registry.gitlab.steamos.cloud/proton/soldier/sdk:$(protonsdk_version)
else
protonsdk_version := $(shell grep '^arg_protonsdk_image=' configure.sh|xargs echo|cut -d: -f2)
endif


all: help

.PHONY: help vagrant clean configure proton install deploy module protonsdk

help:
	@echo "Proton Makefile instructions"
	@echo ""
	@echo "\"Quick start\" Makefile targets:"
	@echo "  install - Install Proton into current user's Steam installation"
	@echo "  redist - Build a package suitable for manual installation or distribution"
	@echo "           to other users in vagrant_share/ named after the nearest git tag"
	@echo "  deploy - Build Steam deployment files into a directory in vagrant_share/ named"
	@echo "           after the nearest git tag"
	@echo "  clean - Delete the Proton build directory"
	@echo ""
	@echo "Configuration variables:"
	@echo "  build_name - The name of the build, will be displayed in Steam. Defaults to"
	@echo "               current proton.git branch name if available. A new build dir"
	@echo "               will be created for each build_name, so if you override this,"
	@echo "               remember to always set it!"
	@echo "               Current build name: $(_build_name)"
	@echo "  unstripped - Set to non-empty to avoid stripping installed library files."
	@echo "  enable_ccache - Enabled by default, set to 0 to disable ccache."
	@echo "  disable_vagrant - Set to 1 to disable vagrant and build directly on the host."
	@echo "  protonsdk_version - Version of the proton sdk image to use for building,"
	@echo "                      use protonsdk_version=local to build it locally."
	@echo ""
	@echo "Development targets:"
	@echo "  vagrant - Start Vagrant VM"
	@echo "  configure - Configure Proton build directory"
	@echo "  proton - Build Proton"
	@echo ""
	@echo "  The following targets are development targets only useful after building Proton."
	@echo "  module - Rebuild a single Wine module and copy into vagrant_share/."
	@echo "           Specify module variable: make module=kernel32 module"
	@echo "  dxvk - Rebuild DXVK and copy it into vagrant_share/."
	@echo "  lsteamclient - Rebuild the Steam client wrapper and copy it into vagrant_share/."
	@echo ""
	@echo "Examples:"
	@echo "  make install - Build Proton and install into this user's Steam installation,"
	@echo "      with the current Proton branch name as the tool's name."
	@echo ""
	@echo "  make redist - Build a Proton redistribution package in a tagged directory"
	@echo "      in vagrant_share/."
	@echo ""
	@echo "  make build_name=mytest install - Build Proton with the tool name \"mytest\" and"
	@echo "      install into this user's Steam installation."
	@echo ""
	@echo "  make build_name=mytest module=dsound module - Build only the dsound module"
	@echo "      in the \"mytest\" build directory and place it into vagrant_share/dsound/."
	@echo ""
	@echo "Running out of disk space in the VM? See resize-vagrant-disk.sh"

ifeq ($(disable_vagrant),1)
VAGRANT_SHELL := $(SHELL)
VAGRANT_DIR := vagrant_share
BUILD_DIR := ../$(BUILD_DIR)
else
VAGRANT_SHELL := vagrant ssh
VAGRANT_DIR := /vagrant
endif

vagrant: private SHELL := $(SHELL)
vagrant:
ifneq ($(disable_vagrant),1)
	vagrant up
	vagrant rsync debian10
endif

clean: private SHELL := $(VAGRANT_SHELL)
clean: vagrant
	rm -rf $(BUILD_DIR)/

protonsdk: private SHELL := $(VAGRANT_SHELL)
protonsdk: vagrant
	$(MAKE) $(MFLAGS) $(MAKEOVERRIDES) -C proton/docker $(UNSTRIPPED) $(CCACHE_FLAG) PROTONSDK_VERSION=$(protonsdk_version) proton

configure: private SHELL := $(VAGRANT_SHELL)
configure: vagrant
	if [ ! -e $(BUILD_DIR)/Makefile ]; \
		then mkdir -p $(BUILD_DIR); \
		(cd $(BUILD_DIR) && $(CONFIGURE_CMD)); \
	fi

ifeq ($(protonsdk_version),local)
configure: protonsdk
endif

downloads: private SHELL := $(VAGRANT_SHELL)
downloads: configure
ifneq ($(disable_vagrant),1)
	$(MAKE) $(MFLAGS) $(MAKEOVERRIDES) -C $(BUILD_DIR) downloads
endif

proton: private SHELL := $(VAGRANT_SHELL)
proton: downloads
	$(MAKE) $(MFLAGS) $(MAKEOVERRIDES) -C $(BUILD_DIR)/ $(UNSTRIPPED) $(CCACHE_FLAG) dist && \
	echo "Proton built in VM. Use 'install' or 'deploy' targets to retrieve the build."

ifneq ($(disable_vagrant),1)
install-internal: private STEAM_DIR := $(VAGRANT_DIR)/
endif
install-internal: | vagrant_share/compatibilitytools.d/$(_build_name)
install-internal: private SHELL := $(VAGRANT_SHELL)
install-internal: downloads
	$(MAKE) $(MFLAGS) $(MAKEOVERRIDES) -C $(BUILD_DIR)/ $(UNSTRIPPED) $(CCACHE_FLAG) STEAM_DIR=$(STEAM_DIR) install

install: install-internal
ifneq ($(disable_vagrant),1)
	mkdir -p $(STEAM_DIR)/compatibilitytools.d/
	rm -rf $(STEAM_DIR)/compatibilitytools.d/$(_build_name)/files/ #remove proton's internal files, but preserve user_settings etc from top-level
	cp -Rf --no-dereference --preserve=mode,links vagrant_share/compatibilitytools.d/$(_build_name) $(STEAM_DIR)/compatibilitytools.d/
endif
	echo "Proton installed to your local Steam installation"

redist: | vagrant_share/$(DEPLOY_DIR)
redist: private SHELL := $(VAGRANT_SHELL)
redist: downloads
	rm -rf $(VAGRANT_DIR)/$(DEPLOY_DIR)/* && \
	$(MAKE) $(MFLAGS) $(MAKEOVERRIDES) -C $(BUILD_DIR)/ $(UNSTRIPPED) $(CCACHE_FLAG) redist && cp -Rf $(BUILD_DIR)/redist/* $(VAGRANT_DIR)/$(DEPLOY_DIR) && \
	echo "Proton build available at vagrant_share/$(DEPLOY_DIR)"

deploy: | vagrant_share/$(DEPLOY_DIR)-deploy
deploy: private SHELL := $(VAGRANT_SHELL)
deploy: downloads
	rm -rf $(VAGRANT_DIR)/$(DEPLOY_DIR)-deploy/* && \
	$(MAKE) $(MFLAGS) $(MAKEOVERRIDES) -C $(BUILD_DIR)/ $(UNSTRIPPED) $(CCACHE_FLAG) deploy && cp -Rf $(BUILD_DIR)/deploy/* $(VAGRANT_DIR)/$(DEPLOY_DIR)-deploy && \
	echo "Proton deployed to vagrant_share/$(DEPLOY_DIR)-deploy"

module: | vagrant_share/$(module)/lib/wine/
module: | vagrant_share/$(module)/lib64/wine/
module: private SHELL := $(VAGRANT_SHELL)
module: downloads
	$(MAKE) $(MFLAGS) $(MAKEOVERRIDES) -C $(BUILD_DIR)/ $(UNSTRIPPED) $(CCACHE_FLAG) module=$(module) module && \
	cp -f $(BUILD_DIR)/obj-wine32/dlls/$(module)/$(module)$(MODULE_SFX)* $(VAGRANT_DIR)/$(module)/lib/wine/ && \
	cp -f $(BUILD_DIR)/obj-wine64/dlls/$(module)/$(module)$(MODULE_SFX)* $(VAGRANT_DIR)/$(module)/lib64/wine/ && \
	find $(VAGRANT_DIR)/$(module)/ -type f -name "*.dll" -printf "%p\0" | xargs --verbose -0 -r -P8 -n3 proton/make/pefixup.py && \
	cp -f $(BUILD_DIR)/obj-wine32/dlls/$(module)/$(module).so $(VAGRANT_DIR)/$(module)/lib/wine/ && \
	cp -f $(BUILD_DIR)/obj-wine64/dlls/$(module)/$(module).so $(VAGRANT_DIR)/$(module)/lib64/wine/ && \
	rm -f $(VAGRANT_DIR)/$(module)/lib*/wine/*.fake

dxvk: | vagrant_share/dxvk/lib/wine/dxvk
dxvk: | vagrant_share/dxvk/lib64/wine/dxvk
dxvk: private SHELL := $(VAGRANT_SHELL)
dxvk: downloads
	$(MAKE) $(MFLAGS) $(MAKEOVERRIDES) -C $(BUILD_DIR)/ $(UNSTRIPPED) $(CCACHE_FLAG) dxvk && \
	cp -f $(BUILD_DIR)/dist/files/lib/wine/dxvk/*.dll $(VAGRANT_DIR)/dxvk/lib/wine/dxvk/ && \
	cp -f $(BUILD_DIR)/dist/files/lib64/wine/dxvk/*.dll $(VAGRANT_DIR)/dxvk/lib64/wine/dxvk/ && \
	find $(VAGRANT_DIR)/dxvk/ -type f -name "*.dll" -printf "%p\0" | xargs --verbose -0 -r -P8 -n3 proton/make/pefixup.py'

vkd3d-proton: | vagrant_share/vkd3d-proton/lib/wine/vkd3d-proton
vkd3d-proton: | vagrant_share/vkd3d-proton/lib64/wine/vkd3d-proton
vkd3d-proton: private SHELL := $(VAGRANT_SHELL)
vkd3d-proton: downloads
	$(MAKE) $(MFLAGS) $(MAKEOVERRIDES) -C $(BUILD_DIR)/ $(UNSTRIPPED) $(CCACHE_FLAG) vkd3d-proton && \
	cp -f $(BUILD_DIR)/dist/files/lib/wine/vkd3d-proton/*.dll $(VAGRANT_DIR)/vkd3d-proton/lib/wine/vkd3d-proton/ && \
	cp -f $(BUILD_DIR)/dist/files/lib64/wine/vkd3d-proton/*.dll $(VAGRANT_DIR)/vkd3d-proton/lib64/wine/vkd3d-proton/ && \
	find $(VAGRANT_DIR)/vkd3d-proton/ -type f -name "*.dll" -printf "%p\0" | xargs --verbose -0 -r -P8 -n3 proton/make/pefixup.py'

lsteamclient: | vagrant_share/lsteamclient/lib/wine
lsteamclient: | vagrant_share/lsteamclient/lib64/wine
lsteamclient: private SHELL := $(VAGRANT_SHELL)
lsteamclient: downloads
	$(MAKE) $(MFLAGS) $(MAKEOVERRIDES) -C $(BUILD_DIR)/ $(UNSTRIPPED) $(CCACHE_FLAG) lsteamclient && \
	cp -f $(BUILD_DIR)/dist/files/lib/wine/lsteamclient.dll.so $(VAGRANT_DIR)/lsteamclient/lib/wine && \
	cp -f $(BUILD_DIR)/dist/files/lib64/wine/lsteamclient.dll.so $(VAGRANT_DIR)/lsteamclient/lib64/wine

vrclient: | vagrant_share/vrclient/lib/wine
vrclient: | vagrant_share/vrclient/lib64/wine
vrclient: private SHELL := $(VAGRANT_SHELL)
vrclient: downloads
	$(MAKE) $(MFLAGS) $(MAKEOVERRIDES) -C $(BUILD_DIR)/ $(UNSTRIPPED) $(CCACHE_FLAG) vrclient && \
	cp -f $(BUILD_DIR)/dist/files/lib/wine/vrclient.dll.so $(VAGRANT_DIR)/vrclient/lib/wine && \
	cp -f $(BUILD_DIR)/dist/files/lib64/wine/vrclient_x64.dll.so $(VAGRANT_DIR)/vrclient/lib64/wine

wineopenxr: | vagrant_share/wineopenxr/lib/wine
wineopenxr: | vagrant_share/wineopenxr/lib64/wine
wineopenxr: private SHELL := $(VAGRANT_SHELL)
wineopenxr: downloads
	$(MAKE) $(MFLAGS) $(MAKEOVERRIDES) -C $(BUILD_DIR)/ $(UNSTRIPPED) $(CCACHE_FLAG) wineopenxr && \
	cp -f $(BUILD_DIR)/dist/files/lib64/wine/wineopenxr.dll.so $(VAGRANT_DIR)/wineopenxr/lib64/wine

vagrant_share/%:
	mkdir -p $@
