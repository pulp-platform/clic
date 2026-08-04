// Copyright 2025 ETH Zurich and University of Bologna.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// SPDX-License-Identifier: Apache-2.0

`include "register_interface/typedef.svh"

package clic_synth_pkg;

  localparam int N_SOURCE   = 256;
  localparam int SRC_W      = $clog2(N_SOURCE);
  localparam int INTCTLBITS = 8;
  localparam bit SSCLIC     = 1;
  localparam bit USCLIC     = 0;

  `REG_BUS_TYPEDEF_ALL(reg, logic [31:0], logic [31:0], logic [3:0])

endpackage
