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

module clic_reg_adapter import mclic_reg_pkg::*; import clicint_reg_pkg::*; #(
  parameter int N_SOURCE = 32,
  parameter int INTCTLBITS = 8
)(
  input logic                 clk_i,
  input logic                 rst_ni,

  input  mclic_reg_pkg::mclic_reg2hw_t mclic_reg2hw,

  input  clicint_reg_pkg::clicint_reg2hw_t [N_SOURCE-1:0] clicint_reg2hw,
  output clicint_reg_pkg::clicint_hw2reg_t [N_SOURCE-1:0] clicint_hw2reg,

  output logic [7:0]          intctl_o [N_SOURCE],
  output logic [1:0]          intmode_o [N_SOURCE],
  output logic [N_SOURCE-1:0] shv_o,
  output logic [N_SOURCE-1:0] ip_sw_o,
  output logic [N_SOURCE-1:0] ie_o,
  output logic [N_SOURCE-1:0] le_o,

  input logic [N_SOURCE-1:0]  ip_i
);

  // We only support positive edge triggered and positive level triggered
  // interrupts atm. Either we hardware the trig.q[1] bit correctly or we
  // implement all modes
  for (genvar i = 0; i < N_SOURCE; i++) begin : gen_reghw
    assign intctl_o[i] = clicint_reg2hw[i].clicint.ctl.q;
    assign intmode_o[i] = clicint_reg2hw[i].clicint.attr_mode.q;
    assign shv_o[i] = clicint_reg2hw[i].clicint.attr_shv.q;
    assign ip_sw_o[i] = clicint_reg2hw[i].clicint.ip.q;
    assign ie_o[i] = clicint_reg2hw[i].clicint.ie.q;
    assign clicint_hw2reg[i].clicint.ip.de = 1'b1; // Always write
    assign clicint_hw2reg[i].clicint.ip.d  = ip_i[i];
    assign le_o[i] = clicint_reg2hw[i].clicint.attr_trig.q[0];
  end

endmodule // clic_reg_adapter
