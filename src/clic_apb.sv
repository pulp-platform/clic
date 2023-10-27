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

// Author: Robert Balas (balasr@iis.ee.ethz.ch)

// SPDX-License-Identifier: Apache-2.0

`include "register_interface/typedef.svh"
`include "register_interface/assign.svh"

module clic_apb #(
  parameter int           N_SOURCE = 256,
  parameter int           N_PIPE = 1,
  parameter int           INTCTLBITS = 8,
  parameter bit           SSCLIC = 0,
  parameter bit           USCLIC = 0,
  parameter bit           VSCLIC = 0,
  parameter int unsigned  N_VSCTXTS = 0,
  parameter bit           VSPRIO = 0,
  parameter int           VsprioWidth = 1,

  // do not edit below, these are derived
  localparam int unsigned REG_BUS_ADDR_WIDTH = 32,
  localparam int unsigned REG_BUS_DATA_WIDTH = 32,
  localparam int          SrcW = $clog2(N_SOURCE),
  localparam int unsigned MAX_VSCTXTS = 64, // up to 64 VS contexts
  localparam int unsigned VSID_W = $clog2(MAX_VSCTXTS)
)(
  input logic                           clk_i,
  input logic                           rst_ni,

  // Bus Interface (device)
  input logic                           penable_i,
  input logic                           pwrite_i,
  input logic [REG_BUS_ADDR_WIDTH-1:0]  paddr_i,
  input logic                           psel_i,
  input logic [REG_BUS_DATA_WIDTH-1:0]  pwdata_i,
  output logic [REG_BUS_DATA_WIDTH-1:0] prdata_o,
  output logic                          pready_o,
  output logic                          pslverr_o,

  // Interrupt Sources
  input [N_SOURCE-1:0]                  intr_src_i,

  // Interrupt notification to core
  output                                irq_valid_o,
  input                                 irq_ready_i,
  output [SrcW-1:0]                     irq_id_o,
  output [7:0]                          irq_level_o,
  output logic                          irq_shv_o,
  output logic [1:0]                    irq_priv_o,
  output logic [VSID_W-1:0]             irq_vsid_o,
  output logic                          irq_v_o,
  output logic                          irq_kill_req_o,
  input logic                           irq_kill_ack_i

);


  REG_BUS #(
    .ADDR_WIDTH (REG_BUS_ADDR_WIDTH),
    .DATA_WIDTH (REG_BUS_DATA_WIDTH)
  ) reg_bus (clk_i);

  apb_to_reg i_apb_to_reg (
    .clk_i,
    .rst_ni,
    .penable_i,
    .pwrite_i,
    .paddr_i,
    .psel_i,
    .pwdata_i,
    .prdata_o,
    .pready_o,
    .pslverr_o,
    .reg_o     (reg_bus)
  );

  typedef logic [REG_BUS_ADDR_WIDTH-1:0] addr_t;
  typedef logic [REG_BUS_DATA_WIDTH-1:0] data_t;
  typedef logic [REG_BUS_DATA_WIDTH/8-1:0] strb_t;

  `REG_BUS_TYPEDEF_REQ(reg_a32_d32_req_t, addr_t, data_t, strb_t)
  `REG_BUS_TYPEDEF_RSP(reg_a32_d32_rsp_t, data_t)

  reg_a32_d32_req_t clic_req;
  reg_a32_d32_rsp_t clic_rsp;

  assign clic_req.addr  = reg_bus.addr;
  assign clic_req.write = reg_bus.write;
  assign clic_req.wdata = reg_bus.wdata;
  assign clic_req.wstrb = reg_bus.wstrb;
  assign clic_req.valid = reg_bus.valid;

  assign reg_bus.rdata = clic_rsp.rdata;
  assign reg_bus.error = clic_rsp.error;
  assign reg_bus.ready = clic_rsp.ready;

  clic #(
    .reg_req_t ( reg_a32_d32_req_t ),
    .reg_rsp_t ( reg_a32_d32_rsp_t ),
    .N_SOURCE  ( N_SOURCE          ),
    .N_PIPE    ( N_PIPE            ),
    .INTCTLBITS( INTCTLBITS        ),
    .SSCLIC    ( SSCLIC            ),
    .USCLIC    ( USCLIC            ),
    .VSCLIC    ( VSCLIC            ),
    .N_VSCTXTS ( N_VSCTXTS         ),
    .VSPRIO    ( VSPRIO            ),
    .VsprioWidth(VsprioWidth       )
  ) i_clic (
    .clk_i,
    .rst_ni,
     // Bus Interface
    .reg_req_i   ( clic_req       ),
    .reg_rsp_o   ( clic_rsp       ),
    // Interrupt Sources
    .intr_src_i,
    // Interrupt notification to core
    .irq_valid_o,
    .irq_ready_i,
    .irq_id_o,
    .irq_level_o,
    .irq_shv_o,
    .irq_priv_o,
    .irq_vsid_o,
    .irq_v_o,
    .irq_kill_req_o,
    .irq_kill_ack_i
  );

endmodule // clic_apb
