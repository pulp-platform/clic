# Copyright 2026 ETH Zurich and University of Bologna.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

BENDER    ?= bender
OSEDA     ?= oseda
VERILATOR ?= $(OSEDA) verilator
QUESTA    ?= questa-2025.3
VSIM      ?= $(QUESTA) vsim

# clic.mk defaults PEAKRDL to a bare `peakrdl`, since an importing project
# supplies its own. Standalone, this repository provisions the pinned version
# with uv. Set before the include so the fragment's ?= does not override it.
PEAKRDL   ?= uv run --group regs peakrdl

TB        := tb_clic

RDL_DIR   := rdl
SRC_DIR   := src
TEST_DIR  := test
VLT_DIR   := $(TEST_DIR)/verilator
VSIM_DIR  := $(TEST_DIR)/vsim

BENDER_TARGETS := -t rtl -t test_clic

# Testbench parameters, override on the command line.
N_SOURCE   ?= 16
INTCTLBITS ?= 8
SSCLIC     ?= 1
USCLIC     ?= 0
VSCLIC     ?= 1
N_VSCTXTS  ?= 4
VSPRIO     ?= 1
VSPRIO_W   ?= 1

SEED       ?= 1

TB_PARAMS := N_SOURCE INTCTLBITS SSCLIC USCLIC VSCLIC N_VSCTXTS VSPRIO VSPRIO_W

PARAM_FLAGS := $(foreach p,$(TB_PARAMS),-G$(p)=$($(p)))

.PHONY: all vlt-sim vsim-sim checkout regs clean

all: vlt-sim

checkout:
	$(BENDER) checkout

##############
# Registers  #
##############

# Memory-map views come from clic.mk, the fragment a superproject imports. Here
# it only serves the testbench, so CLIC_ROOT is this repository.

CLIC_ROOT        := .
CLIC_NUM_SOURCES := 4096
CLIC_NUM_VSCTXTS := 64
CLIC_VSCLIC      := 1
# 2**ceil(log2((2 + 64) * 32KiB)) = 4MiB, matching ADDR_W in clic.sv at 64 contexts.
CLIC_WINDOW_SIZE := 0x400000
CLIC_DEFS        := $(TEST_DIR)/clic_reg_defs.svh

include clic.mk

# RTL register block generation. This is a maintainer target, not part of
# clic.mk: the blocks take no elaboration-time parameters, so they are identical
# for every configuration and are checked into src/. A superproject consumes
# them through Bender and never regenerates them; only a change to a .rdl file
# requires running this.
#
#   --cpuif apb4-flat       individual APB4 ports rather than a SystemVerilog
#                           interface, so clic.sv can fan the channel out itself
#   --default-reset arst_n  match the asynchronous active-low rst_ni used
#                           throughout the IP
REGBLOCK_FLAGS ?= --cpuif apb4-flat --default-reset arst_n

REG_BLOCKS := cliccfg clicint clicintv clicvs
REG_SRCS   := $(foreach b,$(REG_BLOCKS),$(SRC_DIR)/$(b)_reg.sv $(SRC_DIR)/$(b)_reg_pkg.sv)

# PeakRDL emits no license header and regblock has no option for one, so it is
# prepended afterwards.
REG_LICENSE := // Copyright 2026 ETH Zurich and University of Bologna.\n// Licensed under the Apache License, Version 2.0, see LICENSE for details.\n// SPDX-License-Identifier: Apache-2.0\n

regs: $(REG_SRCS)

$(SRC_DIR)/%_reg.sv $(SRC_DIR)/%_reg_pkg.sv: $(RDL_DIR)/%.rdl $(RDL_DIR)/clic_regs.rdl
	$(PEAKRDL) regblock $< -o $(SRC_DIR) -I $(RDL_DIR) $(REGBLOCK_FLAGS) \
		--module-name $*_reg --package-name $*_reg_pkg
	@sed -i '1i$(REG_LICENSE)' $(SRC_DIR)/$*_reg.sv $(SRC_DIR)/$*_reg_pkg.sv

##############
# Verilator  #
##############

# Verilator resolves parameters at compile time, so every distinct parameter set
# needs its own build.
empty :=
space := $(empty) $(empty)
VLT_OBJ := obj_$(subst $(space),_,$(strip $(foreach p,$(TB_PARAMS),$($(p)))))
VLT_BIN := $(VLT_DIR)/$(VLT_OBJ)/$(TB)

# Kept inside the object directory so concurrent configurations do not overwrite
# each other's logs.
VLT_BUILD_LOG := $(VLT_DIR)/$(VLT_OBJ)/build.log
VLT_SIM_LOG   := $(VLT_DIR)/$(VLT_OBJ)/sim.log

VLT_FLAGS := --binary --timing -j 0 \
             --top-module $(TB) \
             $(PARAM_FLAGS) \
             --Mdir $(VLT_DIR)/$(VLT_OBJ) \
             -o $(TB) \
             -Wno-fatal

$(VLT_DIR):
	mkdir -p $(VLT_DIR)

$(VLT_DIR)/sources.f: Bender.yml Bender.lock | $(VLT_DIR)
	$(BENDER) script verilator $(BENDER_TARGETS) > $@

$(VLT_BIN): $(VLT_DIR)/sources.f $(CLIC_DEFS) $(wildcard src/*.sv) $(wildcard test/*.sv)
	@echo "verilating $(TB) ($(PARAM_FLAGS))..."
	@mkdir -p $(VLT_DIR)/$(VLT_OBJ)
	@$(VERILATOR) $(VLT_FLAGS) -f $(VLT_DIR)/sources.f > $(VLT_BUILD_LOG) 2>&1 || \
		(echo "VERILATOR BUILD FAILED"; cat $(VLT_BUILD_LOG); false)
	@test -x $@ || (echo "VERILATOR BUILD FAILED"; cat $(VLT_BUILD_LOG); false)

vlt-sim: $(VLT_BIN)
	cd $(VLT_DIR) && $(OSEDA) ./$(VLT_OBJ)/$(TB) +verilator+seed+$(SEED) 2>&1 | tee $(VLT_OBJ)/sim.log
	@grep -q " result     : PASS" $(VLT_SIM_LOG) || (echo "SIMULATION FAILED"; false)

##############
# QuestaSim  #
##############

$(VSIM_DIR):
	mkdir -p $(VSIM_DIR)

$(VSIM_DIR)/compile.tcl: Bender.yml Bender.lock | $(VSIM_DIR)
	$(BENDER) script vsim $(BENDER_TARGETS) -t simulation > $@

$(VSIM_DIR)/compiled.stamp: $(VSIM_DIR)/compile.tcl $(CLIC_DEFS) $(wildcard src/*.sv) $(wildcard test/*.sv)
	cd $(VSIM_DIR) && $(VSIM) -c -do "source compile.tcl; quit" | tee compile.log
	@if grep -qE "^# Errors: [1-9]" $(VSIM_DIR)/compile.log; then \
		echo "COMPILATION FAILED"; grep -E "^# \*\* Error" $(VSIM_DIR)/compile.log; false; \
	fi
	@touch $@

vsim-sim: $(VSIM_DIR)/compiled.stamp
	cd $(VSIM_DIR) && $(VSIM) -c -voptargs="+acc" $(PARAM_FLAGS) \
		-sv_seed $(SEED) $(TB) -do "run -all; quit" | tee sim.log
	@grep -q " result     : PASS" $(VSIM_DIR)/sim.log || (echo "SIMULATION FAILED"; false)

clean: clic-clean
	rm -rf $(VLT_DIR) $(VSIM_DIR)
