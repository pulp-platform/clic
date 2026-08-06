# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Import this GNU Make fragment in your project's makefile to derive views of
# the CLIC memory map for your configuration:
#
#     CLIC_ROOT ?= $(shell bender path clic)
#     include $(CLIC_ROOT)/clic.mk
#
# Targets:
#   clic-hdr    generate a C header for the CLIC memory map      -> $(CLIC_HDR)
#   clic-defs   generate a SystemVerilog `define header for it   -> $(CLIC_DEFS)
#
# Both are generated from rdl/clic.rdl and describe the same thing in different
# formats. They are not checked in, because they depend on how the IP is
# configured: set CLIC_NUM_SOURCES, CLIC_NUM_VSCTXTS and CLIC_VSCLIC to match
# your instantiation, and CLIC_HDR / CLIC_DEFS to where you want the output.
#
# To pull the register definitions into a larger address map instead of
# exporting a header, include rdl/clic_regs.rdl (register types) or rdl/clic.rdl
# (the whole CLIC map) from your own SystemRDL and pass -I $(CLIC_ROOT)/rdl.

BENDER    ?= bender
CLIC_ROOT ?= $(shell $(BENDER) path clic)

# Supplied by the importing project, so that everything it generates comes from
# one PeakRDL rather than this IP quietly running a second one. To use the
# version pinned in this repository's pyproject.toml instead, set
#   PEAKRDL := uv run --project $(CLIC_ROOT) --group regs peakrdl
PEAKRDL   ?= peakrdl

# Must match the parameters the CLIC is instantiated with.
CLIC_NUM_SOURCES ?= 256
CLIC_NUM_VSCTXTS ?= 4
CLIC_VSCLIC      ?= 1

# Size of the address window the CLIC claims, which is larger than the registers
# in it: clic.sv decodes paddr[ADDR_W-1:0] with
#   ADDR_W = $clog2((N_VSCTXTS + 2) * 32 * 1024)
# so this must be 2**ADDR_W. SystemRDL has no clog2, so it cannot be derived
# from CLIC_NUM_VSCTXTS here. The default covers 1..6 VS contexts; raise it in
# step with CLIC_NUM_VSCTXTS (64 contexts need 0x400000). Too small a value is
# reported by PeakRDL as an overlap rather than silently truncating.
CLIC_WINDOW_SIZE ?= 0x40000

CLIC_RDL_DIR := $(CLIC_ROOT)/rdl

# Where the generated views land. Override from the superproject.
CLIC_HDR  ?= $(CLIC_ROOT)/clic_regs.h
CLIC_DEFS ?= $(CLIC_ROOT)/test/clic_reg_defs.svh

# Every description shares the register definitions in clic_regs.rdl, so a
# change there must regenerate everything.
CLIC_RDL_DEPS := $(CLIC_RDL_DIR)/clic_regs.rdl

CLIC_MAP_FLAGS := -P NumSources=$(CLIC_NUM_SOURCES) -P NumVsCtxts=$(CLIC_NUM_VSCTXTS)
CLIC_MAP_FLAGS += -P WindowSize=$(CLIC_WINDOW_SIZE)
ifeq ($(CLIC_VSCLIC),1)
CLIC_MAP_FLAGS += -D CLIC_VSCLIC
endif

CLIC_LICENSE_STR := Copyright 2026 ETH Zurich and University of Bologna.\nLicensed under the Apache License, Version 2.0, see LICENSE for details.\nSPDX-License-Identifier: Apache-2.0

.PHONY: clic-hdr clic-defs clic-clean

clic-hdr: $(CLIC_HDR)

clic-defs: $(CLIC_DEFS)

$(CLIC_HDR): $(CLIC_RDL_DIR)/clic.rdl $(CLIC_RDL_DEPS)
	@mkdir -p $(dir $@)
	$(PEAKRDL) raw-header $< -o $@ -I $(CLIC_RDL_DIR) --format c $(CLIC_MAP_FLAGS) \
		--license_str "$(CLIC_LICENSE_STR)"

$(CLIC_DEFS): $(CLIC_RDL_DIR)/clic.rdl $(CLIC_RDL_DEPS)
	@mkdir -p $(dir $@)
	$(PEAKRDL) raw-header $< -o $@ -I $(CLIC_RDL_DIR) --format svh $(CLIC_MAP_FLAGS) \
		--license_str "$(CLIC_LICENSE_STR)"

clic-clean:
	rm -f $(CLIC_HDR) $(CLIC_DEFS)
