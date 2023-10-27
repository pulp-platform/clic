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

module clic import mclic_reg_pkg::*; import clicint_reg_pkg::*; import clicintv_reg_pkg::*; import clicvs_reg_pkg::*; #(
  parameter type reg_req_t = logic,
  parameter type reg_rsp_t = logic,
  parameter int  N_PIPE   = 1, // Number of pipeline stages in priority tree. Increases interrupt latency.
  parameter int  N_SOURCE = 256,
  parameter int  INTCTLBITS = 8,
  parameter bit  SSCLIC = 0,
  parameter bit  USCLIC = 0,
  parameter bit  VSCLIC = 0, // enable vCLIC (requires SSCLIC)

  // vCLIC dependent parameters
  parameter int unsigned N_VSCTXTS = 0, // Number of Virtual Contexts supported.
                                        // This implementation assumes CLIC is mapped to an address
                                        // range that allows up to 64 contexts (at least 512KiB)
  parameter bit  VSPRIO = 0,            // Enable VS prioritization (requires VSCLIC)
  parameter int  VsprioWidth = 1,       // N of VS priority bits (must be set accordingly to the `clicvs` register width)

  // do not edit below, these are derived
  localparam int SRC_W = $clog2(N_SOURCE),
  localparam int unsigned MAX_VSCTXTS = 64, // up to 64 VS contexts
  localparam int unsigned VSID_W = $clog2(MAX_VSCTXTS)
)(
  input logic        clk_i,
  input logic        rst_ni,

  // Bus Interface (device)
  input reg_req_t    reg_req_i,
  output reg_rsp_t   reg_rsp_o,

  // Interrupt Sources
  input [N_SOURCE-1:0] intr_src_i,

  // Interrupt notification to core
  output logic              irq_valid_o,
  input  logic              irq_ready_i,
  output logic [SRC_W-1:0]  irq_id_o,
  output logic [7:0]        irq_level_o,
  output logic              irq_shv_o,
  output logic [1:0]        irq_priv_o,
  output logic [VSID_W-1:0] irq_vsid_o,
  output logic              irq_v_o,
  output logic              irq_kill_req_o,
  input  logic              irq_kill_ack_i
);

  if (USCLIC)
    $fatal(1, "usclic mode is not supported");

  if (VSCLIC) begin
    if (N_VSCTXTS <= 0 || N_VSCTXTS > MAX_VSCTXTS)
      $fatal(1, "vsclic extension requires N_VSCTXTS in [1, 64]");
    if (!SSCLIC)
      $fatal(1, "vsclic extension requires ssclic");
  end else begin
    if(VSPRIO)
      $fatal(1, "vsprio extension requires vsclic");
  end

  localparam logic [1:0] U_MODE = 2'b00;
  localparam logic [1:0] S_MODE = 2'b01;
  localparam logic [1:0] M_MODE = 2'b11;

  ///////////////////////////////////////////////////
  //            CLIC internal addressing           //
  ///////////////////////////////////////////////////
  //
  // The address range is divided into blocks of 32KB.
  // There is one block each for S-mode and M-mode,
  // and there are up to MAX_VSCTXTS extra blocks,
  // one per guest VS.
  //
  // M_MODE   : [0x000000 - 0x007fff]
  // S_MODE   : [0x008000 - 0x00ffff]
  // VS_1     : [0x010000 - 0x017fff]
  // VS_2     : [0x018000 - 0x01ffff]
  //   :
  // VS_64    : [0x208000 - 0x20ffff]

  // Some value between 16 (VSCLIC = 0) and 22 (64 VS contexts)
  localparam int unsigned ADDR_W = $clog2((N_VSCTXTS + 2) * 32 * 1024);

  // Each privilege mode address space is aligned to a 32KiB physical memory region
  localparam logic [ADDR_W-1:0] MCLICCFG_START  = 'h00000;
  localparam logic [ADDR_W-1:0] MCLICCFG_END    = 'h00800;
  localparam logic [ADDR_W-1:0] MCLICINT_START  = 'h01000;
  localparam logic [ADDR_W-1:0] MCLICINT_END    = 'h04fff;

  localparam logic [ADDR_W-1:0] SCLICCFG_START  = 'h08000;
  localparam logic [ADDR_W-1:0] SCLICINT_START  = 'h09000;
  localparam logic [ADDR_W-1:0] SCLICINT_END    = 'h0cfff;
  localparam logic [ADDR_W-1:0] SCLICINTV_START = 'h0d000;
  localparam logic [ADDR_W-1:0] SCLICINTV_END   = 'h0dfff;

  localparam logic [ADDR_W-1:0] VSCLICPRIO_START = 'h0e000;
  localparam logic [ADDR_W-1:0] VSCLICPRIO_END   = 'h0efff;

  // VS `i` (1 <= i <= 64) will be mapped to VSCLIC*(i) address space
  `define VSCLICCFG_START(i)  ('h08000 * (i + 1))
  `define VSCLICINT_START(i)  ('h08000 * (i + 1) + 'h01000)
  `define VSCLICINT_END(i)    ('h08000 * (i + 1) + 'h04fff)

  mclic_reg2hw_t mclic_reg2hw;

  clicint_reg2hw_t [N_SOURCE-1:0] clicint_reg2hw;
  clicint_hw2reg_t [N_SOURCE-1:0] clicint_hw2reg;

  clicintv_reg2hw_t [(N_SOURCE/4)-1:0] clicintv_reg2hw;
  // clicintv_hw2reg_t [(N_SOURCE/4)-1:0] clicintv_hw2reg; // Not needed

  clicvs_reg2hw_t [(MAX_VSCTXTS/4)-1:0] clicvs_reg2hw;
  // clicvs_hw2reg_t [(MAX_VSCTXTS/4)-1:0] clicvs_hw2reg; // Not needed

  logic [7:0] intctl [N_SOURCE];
  logic [7:0] irq_max;

  logic [1:0] intmode [N_SOURCE];
  logic [1:0] irq_mode;

  logic [VSID_W-1:0] vsid [N_SOURCE]; // Per-IRQ Virtual Supervisor (VS) ID
  logic              intv [N_SOURCE]; // Per-IRQ virtualization bit

  logic [VsprioWidth-1:0] vsprio [MAX_VSCTXTS]; // Per-VS priority

  logic [N_SOURCE-1:0] le; // 0: level-sensitive 1: edge-sensitive
  logic [N_SOURCE-1:0] ip;
  logic [N_SOURCE-1:0] ie;
  logic [N_SOURCE-1:0] ip_sw; // sw-based edge-triggered interrupt
  logic [N_SOURCE-1:0] shv; // Handle per-irq SHV bits

  logic [N_SOURCE-1:0] claim;
  logic                mnxti_cfg;

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
    .N_SOURCE    (N_SOURCE),
    .N_PIPE      (N_PIPE),
    .MAX_VSCTXTS (MAX_VSCTXTS),
    .PrioWidth   (INTCTLBITS),
    .ModeWidth   (2),
    .VsidWidth   (VSID_W),
    .VsprioWidth (VsprioWidth)
  ) i_clic_target (
    .clk_i,
    .rst_ni,

    .ip_i        (ip),
    .ie_i        (ie),
    .le_i        (le),
    .shv_i       (shv),

    .prio_i      (intctl),
    .mode_i      (intmode),
    .intv_i      (intv),
    .vsid_i      (vsid),

    .vsprio_i    (vsprio),

    .claim_o     (claim),

    .irq_valid_o,
    .irq_ready_i,
    .irq_id_o,
    .irq_max_o   (irq_max),
    .irq_mode_o  (irq_mode),
    .irq_v_o,
    .irq_vsid_o,
    .irq_shv_o,

    .irq_kill_req_o,
    .irq_kill_ack_i,

    .mnxti_cfg_i (mnxti_cfg)
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
  logic [ADDR_W-1:0] int_addr;

  reg_req_t [N_SOURCE-1:0] reg_int_req;
  reg_rsp_t [N_SOURCE-1:0] reg_int_rsp;

  // TODO: improve decoding by only deasserting valid
  always_comb begin
    int_addr = reg_all_int_req.addr[ADDR_W-1:2];

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

  // interrupt control and status registers (per interrupt line)
  // 0x???? - 0x???? (machine mode)
  reg_req_t reg_all_v_req;
  reg_rsp_t reg_all_v_rsp;
  logic [ADDR_W-1:0] v_addr;

  reg_req_t [(N_SOURCE/4)-1:0] reg_v_req;
  reg_rsp_t [(N_SOURCE/4)-1:0] reg_v_rsp;

  // VSPRIO register interface signals
  reg_req_t reg_all_vs_req;
  reg_rsp_t reg_all_vs_rsp;
  logic [ADDR_W-1:0] vs_addr;

  reg_req_t [(MAX_VSCTXTS/4)-1:0] reg_vs_req;
  reg_rsp_t [(MAX_VSCTXTS/4)-1:0] reg_vs_rsp;

  if (VSCLIC) begin

    always_comb begin
      reg_v_req       = '0;
      reg_all_v_rsp   = '0;

      v_addr = reg_all_v_req.addr[ADDR_W-1:2];

      reg_v_req[v_addr] = reg_all_v_req;
      reg_all_v_rsp = reg_v_rsp[v_addr];
    end

    for (genvar i = 0; i < (N_SOURCE/4); i++) begin : gen_clic_intv
      clicintv_reg_top #(
        .reg_req_t (reg_req_t),
        .reg_rsp_t (reg_rsp_t)
      ) i_clicintv_reg_top (
        .clk_i,
        .rst_ni,

        .reg_req_i (reg_v_req[i]),
        .reg_rsp_o (reg_v_rsp[i]),

        .reg2hw (clicintv_reg2hw[i]),
        // .hw2reg (clicintv_hw2reg[i]),

        .devmode_i  (1'b1)
      );
    end

    if (VSPRIO) begin

      always_comb begin
        reg_vs_req       = '0;
        reg_all_vs_rsp   = '0;

        vs_addr = reg_all_vs_req.addr[ADDR_W-1:2];

        reg_vs_req[vs_addr] = reg_all_vs_req;
        reg_all_vs_rsp = reg_vs_rsp[vs_addr];
      end

      for(genvar i = 0; i < (MAX_VSCTXTS/4); i++) begin : gen_clic_vs

        clicvs_reg_top #(
          .reg_req_t (reg_req_t),
          .reg_rsp_t (reg_rsp_t)
        ) i_clicvs_reg_top (
          .clk_i,
          .rst_ni,

          .reg_req_i (reg_vs_req[i]),
          .reg_rsp_o (reg_vs_rsp[i]),

          .reg2hw (clicvs_reg2hw[i]),
          // .hw2reg (clicvs_hw2reg[i]),

          .devmode_i  (1'b1)
        );

      end

    end else begin
      assign clicvs_reg2hw      = '0;
      // assign clicvs_hw2reg   = '0;
      assign reg_vs_req         = '0;
      assign reg_vs_rsp         = '0;
      assign vs_addr            = '0;
      assign reg_all_vs_rsp     = '0;
    end

  end else begin
    // If both V and Vprio are not enabled, tie all to 0'
    // VS
    assign clicintv_reg2hw    = '0;
    assign reg_v_req          = '0;
    assign reg_v_rsp          = '0;
    assign v_addr             = '0;
    assign reg_all_v_rsp      = '0;
    // VSprio
    assign clicvs_reg2hw      = '0;
    assign reg_vs_req         = '0;
    assign reg_vs_rsp         = '0;
    assign vs_addr            = '0;
    assign reg_all_vs_rsp     = '0;
  end

  // top level address decoding and bus muxing

  // Helper signal used to store intermediate address
  logic [ADDR_W-1:0] addr_tmp;

  always_comb begin : clic_addr_decode
    reg_mclic_req   = '0;
    reg_all_int_req = '0;
    reg_all_v_req   = '0;
    reg_all_vs_req  = '0;
    reg_rsp_o       = '0;

    addr_tmp        = '0;

    unique case(reg_req_i.addr[ADDR_W-1:0]) inside
      [MCLICCFG_START:MCLICCFG_END]: begin
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
          addr_tmp = reg_req_i.addr[ADDR_W-1:0] - SCLICINT_START;
          if (intmode[addr_tmp[ADDR_W-1:2]] <= S_MODE) begin
            // check whether the irq we want to access is s-mode or lower
            reg_all_int_req = reg_req_i;
            reg_all_int_req.addr = addr_tmp;
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
      [SCLICINTV_START:SCLICINTV_END]: begin
        if (VSCLIC) begin
          addr_tmp = reg_req_i.addr[ADDR_W-1:0] - SCLICINTV_START;
          reg_all_v_req = reg_req_i;
          reg_all_v_req.addr = addr_tmp;
          addr_tmp = {addr_tmp[ADDR_W-1:2], 2'b0};
          reg_rsp_o = reg_all_v_rsp;
          if(intmode[addr_tmp + 0] > S_MODE) begin
            reg_all_v_req.wdata[7:0] = 8'b0;
            reg_rsp_o.rdata[7:0] = 8'b0;
          end
          if(intmode[addr_tmp + 1] > S_MODE) begin
            reg_all_v_req.wdata[15:8] = 8'b0;
            reg_rsp_o.rdata[15:8] = 8'b0;
          end
          if(intmode[addr_tmp + 2] > S_MODE) begin
            reg_all_v_req.wdata[23:16] = 8'b0;
            reg_rsp_o.rdata[23:16] = 8'b0;
          end
          if(intmode[addr_tmp + 3] > S_MODE) begin
            reg_all_v_req.wdata[31:24] = 8'b0;
            reg_rsp_o.rdata[31:24] = 8'b0;
          end
        end else begin
          // VSCLIC disabled
          reg_rsp_o.rdata = '0;
          reg_rsp_o.error = '0;
          reg_rsp_o.ready = 1'b1;
        end
      end
      [VSCLICPRIO_START:VSCLICPRIO_END]: begin
        if(VSCLIC && VSPRIO) begin
          addr_tmp = reg_req_i.addr[ADDR_W-1:0] - VSCLICPRIO_START;
          reg_all_vs_req = reg_req_i;
          reg_all_vs_req.addr = addr_tmp;
          reg_rsp_o = reg_all_vs_rsp;
        end else begin
          reg_rsp_o.rdata = '0;
          reg_rsp_o.error = '0;
          reg_rsp_o.ready = 1'b1;
        end
      end
      default: begin
        // inaccesible (all zero)
        reg_rsp_o.rdata = '0;
        reg_rsp_o.error = '0;
        reg_rsp_o.ready = 1'b1;
      end
    endcase // unique case (reg_req_i.addr)

    // Match VS address space
    if (VSCLIC) begin
      for (int i = 1; i <= N_VSCTXTS; i++) begin
        if (reg_req_i.addr[ADDR_W-1:0] == `VSCLICCFG_START(i)) begin
            // inaccesible (all zero)
            reg_rsp_o.rdata = '0;
            reg_rsp_o.error = '0;
            reg_rsp_o.ready = 1'b1;
        end else if (`VSCLICINT_START(i) >= reg_req_i.addr[ADDR_W-1:0] &&
                     reg_req_i.addr[ADDR_W-1:0] <= `VSCLICINT_END(i)) begin
          addr_tmp = reg_req_i.addr[ADDR_W-1:0] - `VSCLICINT_START(i);
          if ((intmode[addr_tmp[ADDR_W-1:2]] == S_MODE) &&
              (intv[addr_tmp[ADDR_W-1:2]])              &&
              (vsid[addr_tmp[ADDR_W-1:2]] == i)) begin
            // check whether the irq we want to access is s-mode and its v bit is set and the VSID corresponds
            reg_all_int_req = reg_req_i;
            reg_all_int_req.addr = addr_tmp;
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
    end
  end

  // adapter
  clic_reg_adapter #(
    .N_SOURCE    (N_SOURCE),
    .INTCTLBITS  (INTCTLBITS),
    .MAX_VSCTXTS (MAX_VSCTXTS),
    .VsidWidth   (VSID_W),
    .VsprioWidth (VsprioWidth)
  ) i_clic_reg_adapter (
    .clk_i,
    .rst_ni,

    .mclic_reg2hw,

    .clicint_reg2hw,
    .clicint_hw2reg,

    .clicintv_reg2hw,
    // .clicintv_hw2reg,

    .clicvs_reg2hw,
    // .clicvs_hw2reg,

    .intctl_o  (intctl),
    .intmode_o (intmode),
    .shv_o     (shv),
    .vsid_o    (vsid),
    .intv_o    (intv),
    .vsprio_o  (vsprio),
    .ip_sw_o   (ip_sw),
    .ie_o      (ie),
    .le_o      (le),

    .ip_i      (ip),
    .mnxti_cfg_o(mnxti_cfg)
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

    if (VSCLIC || SSCLIC || USCLIC)
      nmbits[0] = mclic_reg2hw.mcliccfg.nmbits.q[0];

    if ((VSCLIC || SSCLIC) && USCLIC)
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
