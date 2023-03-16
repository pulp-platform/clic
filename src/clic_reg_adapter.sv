// Copyright 2022 ETH Zurich
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

module clic_reg_adapter import clic_reg_pkg::*; #(
  parameter int N_SOURCE = 32,
  parameter int INTCTLBITS = 8
)(
  input logic                 clk_i,
  input logic                 rst_ni,

  input  clic_reg_pkg::clic_reg2hw_t reg2hw,
  output clic_reg_pkg::clic_hw2reg_t hw2reg,

  output logic [7:0]          intctl_o [N_SOURCE],
  output logic [1:0]          intmode_o [N_SOURCE],
  output logic [N_SOURCE-1:0] shv_o,
  output logic [N_SOURCE-1:0] ip_sw_o,
  output logic [N_SOURCE-1:0] ie_o,
  output logic [N_SOURCE-1:0] le_o,

  input logic [N_SOURCE-1:0]  ip_i
);

  if (N_SOURCE != clic_reg_pkg::NumSrc)
    $fatal(1, "CLIC misconfigured: clic_reg_pkg::NumSrc needs to match N_SOURCE");

  if (INTCTLBITS != clic_reg_pkg::ClicIntCtlBits)
    $fatal(1, "CLIC misconfigured: clic_reg_pkg::ClicIntCtlBits needs to match INTCTLBITS");

  // We only support positive edge triggered and positive level triggered
  // interrupts atm. Either we hardware the trig.q[1] bit correctly or we
  // implement all modes
  for (genvar i = 0; i < NumSrc; i++) begin : gen_reghw
    assign intctl_o[i] = reg2hw.clicint[i].ctl.q;
    assign intmode_o[i] = reg2hw.clicint[i].attr_mode.q;
    assign shv_o[i] = reg2hw.clicint[i].attr_shv.q;
    assign ip_sw_o[i] = reg2hw.clicint[i].ip.q;
    assign ie_o[i] = reg2hw.clicint[i].ie.q;
    assign hw2reg.clicint[i].ip.de = 1'b1; // Always write
    assign hw2reg.clicint[i].ip.d  = ip_i[i];
    assign le_o[i] = reg2hw.clicint[i].attr_trig.q[0];
  end

endmodule // clic_reg_adapter
