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

module clic_reg_adapter import mclic_reg_pkg::*; import clicint_reg_pkg::*; import clicintv_reg_pkg::*; import clicvs_reg_pkg::*; #(
  parameter int N_SOURCE = 32,
  parameter int INTCTLBITS = 8,
  parameter int unsigned MAX_VSCTXTS = 64,
  parameter int unsigned VsidWidth = 6,
  parameter int unsigned VsprioWidth = 8
)(
  input logic                 clk_i,
  input logic                 rst_ni,

  input  mclic_reg_pkg::mclic_reg2hw_t mclic_reg2hw,

  input  clicint_reg_pkg::clicint_reg2hw_t [N_SOURCE-1:0] clicint_reg2hw,
  output clicint_reg_pkg::clicint_hw2reg_t [N_SOURCE-1:0] clicint_hw2reg,

  input  clicintv_reg_pkg::clicintv_reg2hw_t [(N_SOURCE/4)-1:0] clicintv_reg2hw,
  // output clicintv_reg_pkg::clicintv_hw2reg_t [(N_SOURCE/4)-1:0] clicintv_hw2reg,

  input  clicvs_reg_pkg::clicvs_reg2hw_t [(MAX_VSCTXTS/4)-1:0] clicvs_reg2hw,
  // output clicvs_reg_pkg::clicvs_hw2reg_t [(MAX_VSCTXTS/4)-1:0] clicvs_hw2reg,

  output logic [7:0]              intctl_o  [N_SOURCE],
  output logic [1:0]              intmode_o [N_SOURCE],
  output logic [VsidWidth-1:0]    vsid_o    [N_SOURCE], // interrupt VS id
  output logic                    intv_o    [N_SOURCE], // interrupt virtualization
  output logic [VsprioWidth-1:0]  vsprio_o  [MAX_VSCTXTS], // VS priority
  output logic [N_SOURCE-1:0] shv_o,
  output logic [N_SOURCE-1:0] ip_sw_o,
  output logic [N_SOURCE-1:0] ie_o,
  output logic [N_SOURCE-1:0] le_o,

  input logic [N_SOURCE-1:0]  ip_i,
  output logic mnxti_cfg_o
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

  for (genvar i = 0; i < N_SOURCE; i = i + 4) begin : gen_reghw_v
    assign vsid_o[i+0] = clicintv_reg2hw[i/4].clicintv.vsid0.q;
    assign intv_o[i+0] = clicintv_reg2hw[i/4].clicintv.v0.q;
    assign vsid_o[i+1] = clicintv_reg2hw[i/4].clicintv.vsid1.q;
    assign intv_o[i+1] = clicintv_reg2hw[i/4].clicintv.v1.q;
    assign vsid_o[i+2] = clicintv_reg2hw[i/4].clicintv.vsid2.q;
    assign intv_o[i+2] = clicintv_reg2hw[i/4].clicintv.v2.q;
    assign vsid_o[i+3] = clicintv_reg2hw[i/4].clicintv.vsid3.q;
    assign intv_o[i+3] = clicintv_reg2hw[i/4].clicintv.v3.q;
  end

  for (genvar i = 0; i < MAX_VSCTXTS; i = i + 4) begin : gen_reghw_vs
    assign vsprio_o[i+0] = clicvs_reg2hw[i/4].vsprio.prio0.q;
    assign vsprio_o[i+1] = clicvs_reg2hw[i/4].vsprio.prio1.q;
    assign vsprio_o[i+2] = clicvs_reg2hw[i/4].vsprio.prio2.q;
    assign vsprio_o[i+3] = clicvs_reg2hw[i/4].vsprio.prio3.q;
  end

  assign mnxti_cfg_o = mclic_reg2hw.clicmnxticonf.q;

endmodule // clic_reg_adapter
