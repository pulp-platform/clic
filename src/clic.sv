// Copyright lowRISC contributors.
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

`include "common_cells/assertions.svh"

module clic import mclic_reg_pkg::*; import clicint_reg_pkg::*; #(
  parameter type reg_req_t = logic,
  parameter type reg_rsp_t = logic,
  parameter int  N_SOURCE = 256,
  parameter int  INTCTLBITS = 8,
  parameter bit  SSCLIC = 0,
  parameter bit  USCLIC = 0,
  // do not edit below, these are derived
  localparam int SRC_W = $clog2(N_SOURCE)
)(
  input logic        clk_i,
  input logic        rst_ni,

  // Bus Interface (device)
  input reg_req_t    reg_req_i,
  output reg_rsp_t   reg_rsp_o,

  // Interrupt Sources
  input [N_SOURCE-1:0] intr_src_i,

  // Interrupt notification to core
  output logic             irq_valid_o,
  input  logic             irq_ready_i,
  output logic [SRC_W-1:0] irq_id_o,
  output logic [7:0]       irq_level_o,
  output logic             irq_shv_o,
  output logic [1:0]       irq_priv_o,
  output logic             irq_kill_req_o,
  input  logic             irq_kill_ack_i
);

  if (USCLIC)
    $fatal(1, "usclic mode is not supported");

  localparam logic [1:0] U_MODE = 2'b00;
  localparam logic [1:0] S_MODE = 2'b01;
  localparam logic [1:0] M_MODE = 2'b11;

  localparam logic [15:0] MCLICCFG_START = 16'h0000;
  localparam logic [15:0] MCLICINT_START = 16'h1000;
  localparam logic [15:0] MCLICINT_END   = 16'h4fff;

  localparam logic [15:0] SCLICCFG_START = 16'h8000;
  localparam logic [15:0] SCLICINT_START = 16'h9000;
  localparam logic [15:0] SCLICINT_END   = 16'hcfff;

  mclic_reg2hw_t mclic_reg2hw;

  clicint_reg2hw_t [N_SOURCE-1:0] clicint_reg2hw;
  clicint_hw2reg_t [N_SOURCE-1:0] clicint_hw2reg;

  logic [7:0] intctl [N_SOURCE];
  logic [7:0] irq_max;

  logic [1:0] intmode [N_SOURCE];
  logic [1:0] irq_mode;

  logic [N_SOURCE-1:0] le; // 0: level-sensitive 1: edge-sensitive
  logic [N_SOURCE-1:0] ip;
  logic [N_SOURCE-1:0] ie;
  logic [N_SOURCE-1:0] ip_sw; // sw-based edge-triggered interrupt
  logic [N_SOURCE-1:0] shv; // Handle per-irq SHV bits

  logic [N_SOURCE-1:0] claim;

  // handle incoming interrupts
  clic_gateway #(
    .N_SOURCE   (N_SOURCE)
  ) i_clic_gateway (
    .clk_i,
    .rst_ni,

    .src_i         (intr_src_i),
    .sw_i          (ip_sw),
    .le_i          (le),

    .claim_i       (claim),

    .ip_o          (ip)
  );

  // generate interrupt depending on ip, ie, level and priority
  clic_target #(
    .N_SOURCE  (N_SOURCE),
    .PrioWidth (INTCTLBITS),
    .ModeWidth (2)
  ) i_clic_target (
    .clk_i,
    .rst_ni,

    .ip_i        (ip),
    .ie_i        (ie),
    .le_i        (le),

    .prio_i      (intctl),
    .mode_i      (intmode),

    .claim_o     (claim),

    .irq_valid_o,
    .irq_ready_i,
    .irq_id_o,
    .irq_max_o   (irq_max),
    .irq_mode_o  (irq_mode),

    .irq_kill_req_o,
    .irq_kill_ack_i
  );

  // configuration registers
  // 0x0000 (machine mode)
  reg_req_t reg_mclic_req;
  reg_rsp_t reg_mclic_rsp;

  mclic_reg_top #(
    .reg_req_t (reg_req_t),
    .reg_rsp_t (reg_rsp_t)
  ) i_mclic_reg_top (
    .clk_i,
    .rst_ni,

    .reg_req_i (reg_mclic_req),
    .reg_rsp_o (reg_mclic_rsp),

    .reg2hw (mclic_reg2hw),

    .devmode_i  (1'b1)
  );

  // interrupt control and status registers (per interrupt line)
  // 0x1000 - 0x4fff (machine mode)
  reg_req_t reg_all_int_req;
  reg_rsp_t reg_all_int_rsp;
  logic [15:0] int_addr;

  reg_req_t [N_SOURCE-1:0] reg_int_req;
  reg_rsp_t [N_SOURCE-1:0] reg_int_rsp;

  // TODO: improve decoding by only deasserting valid
  always_comb begin
    int_addr = reg_all_int_req.addr[15:2];

    reg_int_req = '0;
    reg_all_int_rsp = '0;

    reg_int_req[int_addr] = reg_all_int_req;
    reg_all_int_rsp = reg_int_rsp[int_addr];
  end

  for (genvar i = 0; i < N_SOURCE; i++) begin : gen_clic_int
    clicint_reg_top #(
      .reg_req_t (reg_req_t),
      .reg_rsp_t (reg_rsp_t)
    ) i_clicint_reg_top (
      .clk_i,
      .rst_ni,

      .reg_req_i (reg_int_req[i]),
      .reg_rsp_o (reg_int_rsp[i]),

      .reg2hw (clicint_reg2hw[i]),
      .hw2reg (clicint_hw2reg[i]),

      .devmode_i  (1'b1)
    );
  end

  // configuration registers
  // 0x8000 (supervisor mode)

  // interrupt control and status register
  // 0x9000 - 0xcfff (supervisor mode)
  // mirror

  // top level address decoding and bus muxing
  always_comb begin : clic_addr_decode
    reg_mclic_req = '0;
    reg_all_int_req = '0;
    reg_rsp_o = '0;

    unique case(reg_req_i.addr[15:0]) inside
      MCLICCFG_START: begin
        reg_mclic_req = reg_req_i;
        reg_rsp_o = reg_mclic_rsp;
      end
      [MCLICINT_START:MCLICINT_END]: begin
        reg_all_int_req = reg_req_i;
        reg_all_int_req.addr = reg_req_i.addr - MCLICINT_START;
        reg_rsp_o = reg_all_int_rsp;
      end
      SCLICCFG_START: begin
        if (SSCLIC) begin
          reg_mclic_req = reg_req_i;
          reg_rsp_o = reg_mclic_rsp;
        end
      end
      [SCLICINT_START:SCLICINT_END]: begin
        if (SSCLIC) begin
          reg_all_int_req.addr = reg_req_i.addr - SCLICINT_START;
          if (intmode[reg_all_int_req.addr[15:2]] <= S_MODE) begin
            // check whether the irq we want to access is s-mode or lower
            reg_all_int_req = reg_req_i;
            // Prevent setting interrupt mode to m-mode . This is currently a
            // bit ugly but will be nicer once we do away with auto generated
            // clicint registers
            reg_all_int_req.wdata[23] = 1'b0;
            reg_rsp_o = reg_all_int_rsp;
          end else begin
            // inaccesible (all zero)
            reg_rsp_o.rdata = '0;
            reg_rsp_o.error = '0;
            reg_rsp_o.ready = 1'b1;
          end
        end
      end
      default: begin
        // inaccesible (all zero)
        reg_rsp_o.rdata = '0;
        reg_rsp_o.error = '0;
        reg_rsp_o.ready = 1'b1;
      end
    endcase // unique case (reg_req_i.addr)
  end

  // adapter
  clic_reg_adapter #(
    .N_SOURCE   (N_SOURCE),
    .INTCTLBITS (INTCTLBITS)
  ) i_clic_reg_adapter (
    .clk_i,
    .rst_ni,

    .mclic_reg2hw,

    .clicint_reg2hw,
    .clicint_hw2reg,

    .intctl_o  (intctl),
    .intmode_o (intmode),
    .shv_o     (shv),
    .ip_sw_o   (ip_sw),
    .ie_o      (ie),
    .le_o      (le),

    .ip_i      (ip)
  );

  // Create level and prio signals with dynamic indexing (#bits are read from
  // registers and stored in logic signals)
  logic [3:0] mnlbits;

  always_comb begin
    // Saturate nlbits if nlbits > clicintctlbits (nlbits > 0 && nlbits <= 8)
    mnlbits = INTCTLBITS;
    if (mclic_reg2hw.mcliccfg.mnlbits.q <= INTCTLBITS)
      mnlbits = mclic_reg2hw.mcliccfg.mnlbits.q;
  end

  // Extract SHV bit for the highest level, highest priority pending interrupt
  assign irq_shv_o = shv[irq_id_o];

  logic [7:0] irq_level_tmp;

  always_comb begin
      // Get level value of the highest level, highest priority interrupt from
      // clic_target (still in the form `L-P-1`)
      irq_level_tmp = 8'hff;
      unique case (mnlbits)
        4'h0: begin
          irq_level_tmp = 8'hff;
        end
        4'h1: begin
          irq_level_tmp[7] = irq_max[7];
        end
        4'h2: begin
          irq_level_tmp[7:6] = irq_max[7:6];
        end
        4'h3: begin
          irq_level_tmp[7:5] = irq_max[7:5];
        end
        4'h4: begin
          irq_level_tmp[7:4] = irq_max[7:4];
        end
        4'h5: begin
          irq_level_tmp[7:3] = irq_max[7:3];
        end
        4'h6: begin
          irq_level_tmp[7:2] = irq_max[7:2];
        end
        4'h7: begin
          irq_level_tmp[7:1] = irq_max[7:1];
        end
        4'h8: begin
          irq_level_tmp[7:0] = irq_max[7:0];
        end
        default:
          irq_level_tmp = 8'hff;
      endcase
  end

  logic [1:0] nmbits;

  always_comb begin
    // m-mode only supported means no configuration
    nmbits = 2'b0;

    if (SSCLIC || USCLIC)
      nmbits[0] = mclic_reg2hw.mcliccfg.nmbits.q[0];

    if (SSCLIC && USCLIC)
      nmbits[1] = mclic_reg2hw.mcliccfg.nmbits.q[1];
  end

  logic [1:0] irq_mode_tmp;

  always_comb begin
      // Get mode of the highest level, highest priority interrupt from
      // clic_target (still in the form `L-P-1`)
      irq_mode_tmp = M_MODE;
      unique case (nmbits)
        4'h0: begin
          irq_mode_tmp = M_MODE;
        end
        4'h1: begin
          irq_mode_tmp[1] = irq_mode[1];
        end
        4'h2: begin
          irq_mode_tmp = irq_mode;
        end
        4'h3: begin // this is reserved, not sure what to do
          irq_mode_tmp = irq_mode;
        end
        default:
          irq_mode_tmp = M_MODE;
      endcase
  end


  assign irq_level_o = irq_level_tmp;
  assign irq_priv_o  = irq_mode_tmp;

endmodule // clic
