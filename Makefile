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

TB        := tb_clic

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

.PHONY: all vlt-sim vsim-sim checkout clean

all: vlt-sim

checkout:
	$(BENDER) checkout

##############
# Verilator  #
##############

# Verilator resolves parameters at compile time, so every distinct parameter set
# needs its own build. Keying the object directory on all of them means `make
# vlt-sim N_SOURCE=256` rebuilds instead of silently re-running the previous
# binary. The tag is the parameter values joined in TB_PARAMS order, so the
# defaults give obj_16_8_1_0_1_4_1_1.
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

$(VLT_BIN): $(VLT_DIR)/sources.f $(wildcard src/*.sv) $(wildcard test/*.sv)
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

$(VSIM_DIR)/compiled.stamp: $(VSIM_DIR)/compile.tcl $(wildcard src/*.sv) $(wildcard test/*.sv)
	cd $(VSIM_DIR) && $(VSIM) -c -do "source compile.tcl; quit" | tee compile.log
	@if grep -qE "^# Errors: [1-9]" $(VSIM_DIR)/compile.log; then \
		echo "COMPILATION FAILED"; grep -E "^# \*\* Error" $(VSIM_DIR)/compile.log; false; \
	fi
	@touch $@

vsim-sim: $(VSIM_DIR)/compiled.stamp
	cd $(VSIM_DIR) && $(VSIM) -c -voptargs="+acc" $(PARAM_FLAGS) \
		-sv_seed $(SEED) $(TB) -do "run -all; quit" | tee sim.log
	@grep -q " result     : PASS" $(VSIM_DIR)/sim.log || (echo "SIMULATION FAILED"; false)

clean:
	rm -rf $(VLT_DIR) $(VSIM_DIR)
