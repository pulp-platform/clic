# Copyright 2022 ETH Zurich
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

ifndef $(REGTOOL)
REGTOOL=../../../register_interface/vendor/lowrisc_opentitan/util/regtool.py
endif
ifndef $(NUM_INTERRUPT)
NUM_INTERRUPT=256
endif
ifndef $(CLICINTCTLBITSL)
CLICINTCTLBITS=8
endif

all: clic_reg_adapter.sv clic.hjson headers srcs

clic_reg_adapter.sv: clic_reg_adapter.sv.tpl
	./clic.py -s $(NUM_INTERRUPT) -c $(CLICINTCTLBITS) < $< > $@

srcs: clic_reg_pkg.sv clic_reg_top.sv

clic_reg_pkg.sv clic_reg_top.sv: clic.hjson
	$(REGTOOL) -r clic.hjson -t .

clic.hjson: clic.hjson.tpl
	./clic.py -s $(NUM_INTERRUPT) -c $(CLICINTCTLBITS) < $< > $@

headers: clic.h

clic.h: clic.hjson
	$(REGTOOL)  --cdefines clic.hjson > clic.h

clean:
	rm clic.h clic.hjson clic_reg_adapter.sv clic_reg_pkg.sv clic_reg_top.sv

