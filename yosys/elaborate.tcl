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

set top_design clic_synth_wrap

yosys plugin -i slang.so

yosys read_slang --top ${top_design} -F clic.flist \
    --compat-mode --keep-hierarchy \
    --allow-use-before-declare --ignore-unknown-modules \
    --ignore-assertions -Wno-error=duplicate-definition

yosys hierarchy -top ${top_design}
yosys check

yosys tee -q -o "reports/clic_elaborated.rpt" stat
yosys write_verilog -norename -noexpr -attr2comment out/clic_elaborated.v

exit
