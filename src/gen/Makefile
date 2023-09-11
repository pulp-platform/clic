# Copyright 2023 ETH Zurich
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
# Author: Robert Balas

# Generate C header and SystemVerilog files

REGTOOL = regtool.py

SRCS = clicvs_reg_pkg.sv clicvs_reg_top.sv clicintv_reg_pkg.sv clicintv_reg_top.sv clicint_reg_pkg.sv clicint_reg_top.sv mclic_reg_pkg.sv mclic_reg_top.sv
HDRS = clic.h clicint.h clicintv.h clicvs.h

all: headers srcs

srcs: $(SRCS)

clicvs_reg_pkg.sv clicvs_reg_top.sv: clicvs.hjson
	$(REGTOOL) -r $< -t .

clicintv_reg_pkg.sv clicintv_reg_top.sv: clicintv.hjson
	$(REGTOOL) -r $< -t .

clicint_reg_pkg.sv clicint_reg_top.sv: clicint.hjson
	$(REGTOOL) -r $< -t .

mclic_reg_pkg.sv mclic_reg_top.sv: mclic.hjson
	$(REGTOOL) -r $< -t .

headers: $(HDRS)

clic.h: mclic.hjson
	$(REGTOOL) --cdefines mclic.hjson > $@

clicint.h: clicint.hjson
	$(REGTOOL) --cdefines clicint.hjson > $@

clicintv.h: clicintv.hjson
	$(REGTOOL) --cdefines clicintv.hjson > $@

clicvs.h: clicvs.hjson
	$(REGTOOL) --cdefines clicvs.hjson > $@

.PHONY: install
install:
	cp $(SRCS) ..

.PHONY: clean
clean:
	rm $(HDRS) $(SRCS)

