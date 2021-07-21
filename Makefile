#
# Utility to generate an image tree blob (ITB) comprising a signed System
# Firmware (SYSFW) binary image as released by TI as well as domain-specific
# SYSFW configuration fragments provided in the form of C sources.
#
# Copyright (C) 2018-2019 Texas Instruments Incorporated - http://www.ti.com/
#	Andreas Dannenberg <dannenberg@ti.com>
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#    Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#    Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the
#    distribution.
#
#    Neither the name of Texas Instruments Incorporated nor the names of
#    its contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

SOC = j721e
CONFIG = evm

include soc/$(SOC)/Makefile

BUILD_SRC ?= .
O ?= out
BIN_DIR ?= .

srcroot = $(BUILD_SRC)
soc_srcroot = $(srcroot)/soc/${SOC}/${CONFIG}
objroot = $(O)
soc_objroot = $(objroot)/soc/${SOC}/${CONFIG}

binroot = $(BIN_DIR)

# The HS SYSFW will only work on HS hardware when signed with valid
# keys, warn HS users if the SECDEV environment variable is not set
ifdef HS
ifeq ($(TI_SECURE_DEV_PKG),)
$(warning TI_SECURE_DEV_PKG should be set for HS, defaults may not work)
endif
endif

# If using the default SYSFW make sure to manually copy/populate the unsigned
# image into the root folder of this repository.
SYSFW_PATH ?= ti-$(SCIFS)-firmware-${SOC}-gp.bin
SYSFW_HS_PATH ?= ti-$(SCIFS)-firmware-${SOC}-hs-enc.bin
SYSFW_HS_INNER_CERT_PATH ?= ti-$(SCIFS)-firmware-${SOC}-hs-cert.bin
SYSFW_HS_CERTS_PATH ?= ti-$(SCIFS)-firmware-${SOC}-hs-certs.bin

# Must use FULL Git hash below, as it is used as part of an URL for direct DL
SYSFW_GIT_HASH ?= 1e73d9387980f4d425742738968e55395c19e26c

# URL to download SYSFW release binary from if not provided otherwise
SYSFW_DL_URL ?= https://git.ti.com/processor-firmware/ti-linux-firmware/blobs/raw/$(SYSFW_GIT_HASH)/ti-sysfw/$(SYSFW_PATH)
SYSFW_HS_DL_URL ?= https://git.ti.com/processor-firmware/ti-linux-firmware/blobs/raw/$(SYSFW_GIT_HASH)/ti-sysfw/$(SYSFW_HS_PATH)
SYSFW_HS_INNER_CERT_DL_URL ?= https://git.ti.com/processor-firmware/ti-linux-firmware/blobs/raw/$(SYSFW_GIT_HASH)/ti-sysfw/$(SYSFW_HS_INNER_CERT_PATH)

# Set HS SYSFW image signing key
ifdef HS
KEY ?= $(TI_SECURE_DEV_PKG)/keys/custMpk.pem
else
KEY ?= ti-degenerate-key.pem
endif

CROSS_COMPILE = /usr/bin/arm-linux-gnueabihf-

CFLAGS ?= \
	-fno-builtin \
	-Wall \
	-Iinclude/soc/${SOC} \
	-Isoc/${SOC}/${CONFIG} \
	-Iinclude

ifdef ENABLE_TRACE
CFLAGS += -DENABLE_TRACE
endif

SOURCES ?= \
	board-cfg.c \
	pm-cfg.c \
	rm-cfg.c \
	sec-cfg.c

SOC_SOURCES=$(SOURCES:%.c=$(soc_srcroot)/%.c)
SOC_OBJS=$(SOURCES:%.c=$(soc_objroot)/%.o)

SOC_BINS=$(soc_objroot)/sysfw.bin
SOC_BIN_NAMES=sysfw.bin

SOC_BINS += $(SOURCES:%.c=$(soc_objroot)/%.bin)
SOC_BIN_NAMES += $(SOURCES:%.c=%.bin)

ITB ?= $(binroot)/sysfw-$(SOC)-$(CONFIG).itb
ITS ?= $(soc_objroot)/$(basename $(notdir $(ITB))).its
COMBINED_SYSFW_BRDCFG ?= $(soc_objroot)/combined-sysfw-cfg.bin
COMBINED_TIFS_BRDCFG ?= $(soc_objroot)/combined-tifs-cfg.bin
COMBINED_DM_BRDCFG ?= $(soc_objroot)/combined-dm-cfg.bin

vpath %.itb $(soc_objroot)
vpath %.bin $(soc_objroot)
vpath %.o $(soc_objroot)
vpath %.c $(soc_srcroot)

MKIMAGE ?= mkimage

ifeq ($(shell which python3),)
$(error "No python3 in $(PATH), consider installing python3")
endif

.PHONY: _objtree_build
_objtree_build:
	@mkdir -p $(objroot) $(soc_objroot) $(binroot)

$(SYSFW_PATH):
	@echo "Downloading SYSFW release image..."
	wget $(SYSFW_DL_URL)
	@echo "Download SUCCESS!"

$(SYSFW_HS_PATH):
	@echo "Downloading HS SYSFW release image..."
	wget $(SYSFW_HS_DL_URL)
	@echo "Download SUCCESS!"

$(SYSFW_HS_INNER_CERT_PATH):
	@echo "Downloading HS SYSFW release certificate..."
	wget $(SYSFW_HS_INNER_CERT_DL_URL)
	@echo "Download SUCCESS!"

ifdef HS
$(SYSFW_HS_CERTS_PATH): $(SYSFW_HS_INNER_CERT_PATH)
	@echo "Signing the SYSFW inner certificate with $(KEY) key...";
	./gen_x509_cert.sh -d -c m3 -b $< -o $@ -l $(LOADADDR) -k $(KEY);

$(soc_objroot)/sysfw.bin: $(SYSFW_HS_CERTS_PATH) $(SYSFW_HS_PATH)
	cat $^ > $@
else
$(soc_objroot)/sysfw.bin: $(SYSFW_PATH)
	@if [ -n "$(KEY)" ]; then \
		echo "Signing the SYSFW release image with $(KEY) key..."; \
		./gen_x509_cert.sh -c m3 -b $< -o $@ -l $(LOADADDR) -k $(KEY); \
	else \
		echo "Signing the SYSFW release image with random key..."; \
		./gen_x509_cert.sh -c m3 -b $< -o $@ -l $(LOADADDR); \
	fi
endif

$(ITS): soc_objs $(SOC_BINS)
	./gen_its.sh $(SOC) $(CONFIG) $(SOC_BIN_NAMES) > $@

$(ITB): $(ITS)
	$(MKIMAGE) -f $< -r $@

sysfw.itb: $(ITB)
	@cp $< $@

soc_objs: $(SOC_OBJS)

$(COMBINED_SYSFW_BRDCFG): $(SOC_BINS)
	python3 ./scripts/sysfw_boardcfg_blob_creator.py -b $(soc_objroot)/board-cfg.bin -s $(soc_objroot)/sec-cfg.bin -p $(soc_objroot)/pm-cfg.bin -r $(soc_objroot)/rm-cfg.bin -o $@

$(COMBINED_TIFS_BRDCFG): $(SOC_BINS)
	python3 ./scripts/sysfw_boardcfg_blob_creator.py -b $(soc_objroot)/board-cfg.bin -s $(soc_objroot)/sec-cfg.bin -p $(soc_objroot)/pm-cfg.bin -r $(soc_objroot)/rm-cfg.bin -o $@

$(COMBINED_DM_BRDCFG): $(SOC_BINS)
	python3 ./scripts/sysfw_boardcfg_blob_creator.py -p $(soc_objroot)/pm-cfg.bin -r $(soc_objroot)/rm-cfg.bin -o $@

ifneq (,$(COMBINED_SYSFW_BRDCFG_LOADADDR))
tiboot3.bin: $(SBL) $(SYSFW_PATH) $(COMBINED_SYSFW_BRDCFG)
	./scripts/gen_x509_combined_cert.sh -b $(SBL) -l $(SBL_LOADADDDR) -s $(SYSFW_PATH) -m $(LOADADDR) -d $(COMBINED_SYSFW_BRDCFG) -n $(COMBINED_SYSFW_BRDCFG_LOADADDR) -k $(KEY) -o $@
else
tiboot3.bin: $(SBL) $(SYSFW_PATH) $(COMBINED_TIFS_BRDCFG) $(COMBINED_DM_BRDCFG)
	./scripts/gen_x509_combined_cert.sh -b $(SBL) -l $(SBL_LOADADDDR) -s $(SYSFW_PATH) -m 0x40000 -d $(COMBINED_TIFS_BRDCFG) -n $(COMBINED_TIFS_BRDCFG_LOADADDR) -t $(COMBINED_DM_BRDCFG) -y $(COMBINED_DM_BRDCFG_LOADADDR) -k $(KEY) -o $@
endif

$(soc_objroot)/%.o: %.c
	$(CROSS_COMPILE)gcc $(CFLAGS) -c -o $@-pre-validated $<
	python3 ./scripts/sysfw_boardcfg_validator.py -b $@-pre-validated -i -o $@ -s $(SOC) -l $@.log

# On HS board configuration binaries must be signed
ifdef HS
%.bin.unsigned: %.o
	$(CROSS_COMPILE)objcopy -S -O binary $< $@
%.bin: %.bin.unsigned
	$(TI_SECURE_DEV_PKG)/scripts/secure-binary-image.sh $< $@
else
%.bin: %.o
	$(CROSS_COMPILE)objcopy -S -O binary $< $@
endif

.PHONY: sysfw_version
sysfw_version: $(SYSFW_PATH)
	@echo "SYSFW Version:" `strings $(SYSFW_PATH) | grep -o 'v20[0-9][0-9]\.[0-9][0-9].*(.*'`

.PHONY: clean
clean:
	-rm -f $(SOC_BINS) $(SOC_OBJS)
	-rm -f $(ITB) sysfw.itb
	-rm -f $(ITS)
	-rm -f $(SYSFW_HS_CERTS_PATH)
	-rm -rf $(objroot)

.PHONY: mrproper
mrproper: clean
	-rm -f $(SYSFW_PATH)
	-rm -f $(SYSFW_HS_PATH)
	-rm -f $(SYSFW_HS_INNER_CERT_PATH)
