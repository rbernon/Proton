STEAMRT_VERSION = 0.20201124.0
STEAMRT_URLBASE = registry.gitlab.steamos.cloud

PROTONSDK_URLBASE = rbernon
PROTONSDK_VERSION = $(STEAMRT_VERSION)-0

# this is just for building toolchain, as we do static builds it should
# not have any impact on the end result, but changing it will invalidate
# docker caches, so we need something that don't change much
BASE_IMAGE_i686 = i386/ubuntu:18.04
BASE_IMAGE_x86_64 = ubuntu:18.04

ISL_VERSION = 0.22.1
BINUTILS_VERSION = 2.35
GCC_VERSION = 9.3.0
MINGW_VERSION = 8.0.0
RUST_VERSION = 1.44.1

%.Dockerfile: %.Dockerfile.in
	sed -re 's!@PROTONSDK_URLBASE@!$(PROTONSDK_URLBASE)!g' \
	    -re 's!@BASE_IMAGE@!$(BASE_IMAGE)!g' \
	    -re 's!@ISL_VERSION@!$(ISL_VERSION)!g' \
	    -re 's!@BINUTILS_VERSION@!$(BINUTILS_VERSION)!g' \
	    -re 's!@GCC_VERSION@!$(GCC_VERSION)!g' \
	    -re 's!@MINGW_VERSION@!$(MINGW_VERSION)!g' \
	    -re 's!@RUST_VERSION@!$(RUST_VERSION)!g' \
	    $< >$@

%-i686.Dockerfile.in: %.Dockerfile.in
	sed -re 's!@ARCH@!i686!g' \
	    $< >$@

%-x86_64.Dockerfile.in: %.Dockerfile.in
	sed -re 's!@ARCH@!x86_64!g' \
	    $< >$@

%-linux-gnu.Dockerfile.in: %.Dockerfile.in
	sed -re 's!@TARGET@!linux-gnu!g' \
	    -re 's!@TARGET_FLAGS@!$(TARGET_FLAGS)!g' \
	    $< >$@

%-w64-mingw32.Dockerfile.in: %.Dockerfile.in
	sed -re 's!@TARGET@!w64-mingw32!g' \
	    -re 's!@TARGET_FLAGS@!$(TARGET_FLAGS)!g' \
	    $< >$@

define create-build-base-rules
.PHONY: build-base-$(1)
all build-base: build-base-$(1)
build-base-$(1): BASE_IMAGE = $(BASE_IMAGE_$(1))
build-base-$(1): build-base-$(1).Dockerfile
	rm -rf build; mkdir -p build
	docker build -f $$< \
	  --cache-from=$(PROTONSDK_URLBASE)/build-base-$(1):latest \
	  -t $(PROTONSDK_URLBASE)/build-base-$(1):latest \
	  build
endef

$(eval $(call create-build-base-rules,i686))
$(eval $(call create-build-base-rules,x86_64))

define create-binutils-rules
.PHONY: binutils-$(1)-$(2)
all binutils: binutils-$(1)-$(2)
binutils-$(1)-$(2): binutils-$(1)-$(2).Dockerfile | build-base
	rm -rf build; mkdir -p build
	docker build -f $$< \
	  --cache-from=$(PROTONSDK_URLBASE)/binutils-$(1)-$(2):latest \
	  -t $(PROTONSDK_URLBASE)/binutils-$(1)-$(2):$(BINUTILS_VERSION) \
	  -t $(PROTONSDK_URLBASE)/binutils-$(1)-$(2):latest \
	  build
endef

$(eval $(call create-binutils-rules,i686,w64-mingw32))
$(eval $(call create-binutils-rules,x86_64,w64-mingw32))

define create-mingw-rules
.PHONY: mingw-$(2)-$(1)
all mingw: mingw-$(2)-$(1)
mingw-$(2)-$(1): mingw-$(2)-$(1).Dockerfile | binutils
	rm -rf build; mkdir -p build
	docker build -f $$< \
	  --cache-from=$(PROTONSDK_URLBASE)/mingw-$(2)-$(1):latest \
	  -t $(PROTONSDK_URLBASE)/mingw-$(2)-$(1):$(MINGW_VERSION) \
	  -t $(PROTONSDK_URLBASE)/mingw-$(2)-$(1):latest \
	  build
endef

$(eval $(call create-mingw-rules,i686,headers))
$(eval $(call create-mingw-rules,i686,gcc))
$(eval $(call create-mingw-rules,i686,crt))
$(eval $(call create-mingw-rules,i686,pthreads))
$(eval $(call create-mingw-rules,i686,widl))
$(eval $(call create-mingw-rules,x86_64,headers))
$(eval $(call create-mingw-rules,x86_64,gcc))
$(eval $(call create-mingw-rules,x86_64,crt))
$(eval $(call create-mingw-rules,x86_64,pthreads))
$(eval $(call create-mingw-rules,x86_64,widl))

GCC_TARGET_FLAGS_w64-mingw32 = --disable-shared

define create-gcc-rules
.PHONY: gcc-$(1)-$(2)
all gcc: gcc-$(1)-$(2)
gcc-$(1)-$(2): TARGET_FLAGS = $(GCC_TARGET_FLAGS_$(2))
gcc-$(1)-$(2): gcc-$(1)-$(2).Dockerfile | mingw
	rm -rf build; mkdir -p build
	docker build -f $$< \
	  --cache-from=$(PROTONSDK_URLBASE)/gcc-$(1)-$(2):latest \
	  -t $(PROTONSDK_URLBASE)/gcc-$(1)-$(2):$(GCC_VERSION) \
	  -t $(PROTONSDK_URLBASE)/gcc-$(1)-$(2):latest \
	  build
endef

$(eval $(call create-gcc-rules,i686,w64-mingw32))
$(eval $(call create-gcc-rules,x86_64,w64-mingw32))

.PHONY: proton
all: proton
proton: BASE_IMAGE = $(PROTONSDK_URLBASE)/steamrt:$(STEAMRT_VERSION)
proton: proton.Dockerfile | gcc
	rm -rf build; mkdir -p build
	docker build -f $< \
	  --cache-from=$(PROTONSDK_URLBASE)/proton:latest \
	  -t $(PROTONSDK_URLBASE)/proton:$(PROTONSDK_VERSION) \
	  -t $(PROTONSDK_URLBASE)/proton:latest \
	  build

.PHONY: push
push:
	docker push $(PROTONSDK_URLBASE)/proton:$(PROTONSDK_VERSION)
	docker push $(PROTONSDK_URLBASE)/proton:latest
