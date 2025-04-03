# Copyright 2025 ETH Zurich and University of Bologna.
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

# SPDX-License-Identifier: Apache-2.0

BENDER ?= bender
YOSYS  ?= oseda -2025.03 yosys

YOSYS_ROOT_DIR    ?= $(ROOT)/yosys
YOSYS_OUT_DIR     := $(YOSYS_ROOT_DIR)/out
YOSYS_REPORTS_DIR := $(YOSYS_ROOT_DIR)/reports

$(YOSYS_ROOT_DIR)/clic.flist: Bender.yml
	$(BENDER) script flist-plus -t rtl -t synthesis -t asic -t clic_synth_test > $@

$(YOSYS_OUT_DIR)/clic_elaborated.v: $(YOSYS_ROOT_DIR)/clic.flist
	mkdir -p $(YOSYS_OUT_DIR) $(YOSYS_REPORTS_DIR)
	cd $(YOSYS_ROOT_DIR) && $(YOSYS) -C elaborate.tcl

.PHONY: yosys-elaborate
yosys-elaborate: $(YOSYS_OUT_DIR)/clic_elaborated.v
	@echo "Synthesized CLIC successfully"

.PHONY: yosys-clean
yosys-clean:
	rm -rf $(YOSYS_OUT_DIR) $(YOSYS_REPORTS_DIR) $(YOSYS_ROOT_DIR)/clic.flist
