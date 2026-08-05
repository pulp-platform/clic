// Copyright lowRISC contributors.
// Copyright 2026 ETH Zurich and University of Bologna.
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

module clic
  import clic_pkg::*;
  import cliccfg_reg_pkg::*;
  import clicint_reg_pkg::*;
  import clicintv_reg_pkg::*;
  import clicvs_reg_pkg::*;
  import cf_math_pkg::*;
#(
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
  parameter int  VSPRIO_W = 1,       // N of VS priority bits (must be set accordingly to the `clicvs` register width)

  // APB4 request and response types
  parameter type apb_req_t = logic,
  parameter type apb_rsp_t = logic,

  // do not edit below, these are derived
  localparam int SRC_W = $clog2(N_SOURCE)
)(
  input logic        clk_i,
  input logic        rst_ni,

  // Bus Interface (APB4 device)
  input  apb_req_t   apb_req_i,
  output apb_rsp_t   apb_rsp_o,

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

  localparam int unsigned N_INTV = ceil_div(N_SOURCE, 4);
  localparam int unsigned N_VS   = MAX_VSCTXTS / 4;

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

  // A wider APB address bus is fine, the extra bits are simply never decoded,
  // but a narrower one would silently drop part of the window offset.
  if ($bits(apb_req_i.paddr) < ADDR_W)
    $fatal(1, "apb_req_t address field is too narrow for the configured number of VS contexts");
  if ($bits(apb_req_i.pwdata) != 32)
    $fatal(1, "the CLIC is a 32-bit register block; apb_req_t must have 32-bit pwdata");

  // Each privilege mode address space is aligned to a 32KiB physical memory region
  localparam logic [ADDR_W-1:0] MCLICCFG_START  = 'h00000;
  localparam logic [ADDR_W-1:0] MCLICINT_START  = 'h01000;
  localparam logic [ADDR_W-1:0] MCLICINT_END    = 'h04fff;

  localparam logic [ADDR_W-1:0] SCLICCFG_START  = 'h08000;
  localparam logic [ADDR_W-1:0] SCLICINT_START  = 'h09000;
  localparam logic [ADDR_W-1:0] SCLICINT_END    = 'h0cfff;
  localparam logic [ADDR_W-1:0] SCLICINTV_START = 'h0d000;
  localparam logic [ADDR_W-1:0] SCLICINTV_END   = 'h0dfff;

  localparam logic [ADDR_W-1:0] VSCLICPRIO_START = 'h0e000;
  localparam logic [ADDR_W-1:0] VSCLICPRIO_END   = 'h0efff;

  localparam logic [ADDR_W-1:0] VSCLICCFG_START [MAX_VSCTXTS] = {
    'h10000 + 'h08000 * 0,
    'h10000 + 'h08000 * 1,
    'h10000 + 'h08000 * 2,
    'h10000 + 'h08000 * 3,
    'h10000 + 'h08000 * 4,
    'h10000 + 'h08000 * 5,
    'h10000 + 'h08000 * 6,
    'h10000 + 'h08000 * 7,
    'h10000 + 'h08000 * 8,
    'h10000 + 'h08000 * 9,
    'h10000 + 'h08000 * 10,
    'h10000 + 'h08000 * 11,
    'h10000 + 'h08000 * 12,
    'h10000 + 'h08000 * 13,
    'h10000 + 'h08000 * 14,
    'h10000 + 'h08000 * 15,
    'h10000 + 'h08000 * 16,
    'h10000 + 'h08000 * 17,
    'h10000 + 'h08000 * 18,
    'h10000 + 'h08000 * 19,
    'h10000 + 'h08000 * 20,
    'h10000 + 'h08000 * 21,
    'h10000 + 'h08000 * 22,
    'h10000 + 'h08000 * 23,
    'h10000 + 'h08000 * 24,
    'h10000 + 'h08000 * 25,
    'h10000 + 'h08000 * 26,
    'h10000 + 'h08000 * 27,
    'h10000 + 'h08000 * 28,
    'h10000 + 'h08000 * 29,
    'h10000 + 'h08000 * 30,
    'h10000 + 'h08000 * 31,
    'h10000 + 'h08000 * 32,
    'h10000 + 'h08000 * 33,
    'h10000 + 'h08000 * 34,
    'h10000 + 'h08000 * 35,
    'h10000 + 'h08000 * 36,
    'h10000 + 'h08000 * 37,
    'h10000 + 'h08000 * 38,
    'h10000 + 'h08000 * 39,
    'h10000 + 'h08000 * 40,
    'h10000 + 'h08000 * 41,
    'h10000 + 'h08000 * 42,
    'h10000 + 'h08000 * 43,
    'h10000 + 'h08000 * 44,
    'h10000 + 'h08000 * 45,
    'h10000 + 'h08000 * 46,
    'h10000 + 'h08000 * 47,
    'h10000 + 'h08000 * 48,
    'h10000 + 'h08000 * 49,
    'h10000 + 'h08000 * 50,
    'h10000 + 'h08000 * 51,
    'h10000 + 'h08000 * 52,
    'h10000 + 'h08000 * 53,
    'h10000 + 'h08000 * 54,
    'h10000 + 'h08000 * 55,
    'h10000 + 'h08000 * 56,
    'h10000 + 'h08000 * 57,
    'h10000 + 'h08000 * 58,
    'h10000 + 'h08000 * 59,
    'h10000 + 'h08000 * 60,
    'h10000 + 'h08000 * 61,
    'h10000 + 'h08000 * 62,
    'h10000 + 'h08000 * 63
  };

  // Offsets for VSCLICINT address range computation
  // This unrolled array is necessary to elaborate the design
  // in some synthesis tools.
  localparam logic [ADDR_W-1:0] VSCLICINT_START [MAX_VSCTXTS] = {
    VSCLICCFG_START[0]  + 'h01000,
    VSCLICCFG_START[1]  + 'h01000,
    VSCLICCFG_START[2]  + 'h01000,
    VSCLICCFG_START[3]  + 'h01000,
    VSCLICCFG_START[4]  + 'h01000,
    VSCLICCFG_START[5]  + 'h01000,
    VSCLICCFG_START[6]  + 'h01000,
    VSCLICCFG_START[7]  + 'h01000,
    VSCLICCFG_START[8]  + 'h01000,
    VSCLICCFG_START[9]  + 'h01000,
    VSCLICCFG_START[10] + 'h01000,
    VSCLICCFG_START[11] + 'h01000,
    VSCLICCFG_START[12] + 'h01000,
    VSCLICCFG_START[13] + 'h01000,
    VSCLICCFG_START[14] + 'h01000,
    VSCLICCFG_START[15] + 'h01000,
    VSCLICCFG_START[16] + 'h01000,
    VSCLICCFG_START[17] + 'h01000,
    VSCLICCFG_START[18] + 'h01000,
    VSCLICCFG_START[19] + 'h01000,
    VSCLICCFG_START[20] + 'h01000,
    VSCLICCFG_START[21] + 'h01000,
    VSCLICCFG_START[22] + 'h01000,
    VSCLICCFG_START[23] + 'h01000,
    VSCLICCFG_START[24] + 'h01000,
    VSCLICCFG_START[25] + 'h01000,
    VSCLICCFG_START[26] + 'h01000,
    VSCLICCFG_START[27] + 'h01000,
    VSCLICCFG_START[28] + 'h01000,
    VSCLICCFG_START[29] + 'h01000,
    VSCLICCFG_START[30] + 'h01000,
    VSCLICCFG_START[31] + 'h01000,
    VSCLICCFG_START[32] + 'h01000,
    VSCLICCFG_START[33] + 'h01000,
    VSCLICCFG_START[34] + 'h01000,
    VSCLICCFG_START[35] + 'h01000,
    VSCLICCFG_START[36] + 'h01000,
    VSCLICCFG_START[37] + 'h01000,
    VSCLICCFG_START[38] + 'h01000,
    VSCLICCFG_START[39] + 'h01000,
    VSCLICCFG_START[40] + 'h01000,
    VSCLICCFG_START[41] + 'h01000,
    VSCLICCFG_START[42] + 'h01000,
    VSCLICCFG_START[43] + 'h01000,
    VSCLICCFG_START[44] + 'h01000,
    VSCLICCFG_START[45] + 'h01000,
    VSCLICCFG_START[46] + 'h01000,
    VSCLICCFG_START[47] + 'h01000,
    VSCLICCFG_START[48] + 'h01000,
    VSCLICCFG_START[49] + 'h01000,
    VSCLICCFG_START[50] + 'h01000,
    VSCLICCFG_START[51] + 'h01000,
    VSCLICCFG_START[52] + 'h01000,
    VSCLICCFG_START[53] + 'h01000,
    VSCLICCFG_START[54] + 'h01000,
    VSCLICCFG_START[55] + 'h01000,
    VSCLICCFG_START[56] + 'h01000,
    VSCLICCFG_START[57] + 'h01000,
    VSCLICCFG_START[58] + 'h01000,
    VSCLICCFG_START[59] + 'h01000,
    VSCLICCFG_START[60] + 'h01000,
    VSCLICCFG_START[61] + 'h01000,
    VSCLICCFG_START[62] + 'h01000,
    VSCLICCFG_START[63] + 'h01000
  };

  localparam logic [ADDR_W-1:0] VSCLICINT_END [MAX_VSCTXTS] = {
    VSCLICCFG_START[0]  + 'h04fff,
    VSCLICCFG_START[1]  + 'h04fff,
    VSCLICCFG_START[2]  + 'h04fff,
    VSCLICCFG_START[3]  + 'h04fff,
    VSCLICCFG_START[4]  + 'h04fff,
    VSCLICCFG_START[5]  + 'h04fff,
    VSCLICCFG_START[6]  + 'h04fff,
    VSCLICCFG_START[7]  + 'h04fff,
    VSCLICCFG_START[8]  + 'h04fff,
    VSCLICCFG_START[9]  + 'h04fff,
    VSCLICCFG_START[10] + 'h04fff,
    VSCLICCFG_START[11] + 'h04fff,
    VSCLICCFG_START[12] + 'h04fff,
    VSCLICCFG_START[13] + 'h04fff,
    VSCLICCFG_START[14] + 'h04fff,
    VSCLICCFG_START[15] + 'h04fff,
    VSCLICCFG_START[16] + 'h04fff,
    VSCLICCFG_START[17] + 'h04fff,
    VSCLICCFG_START[18] + 'h04fff,
    VSCLICCFG_START[19] + 'h04fff,
    VSCLICCFG_START[20] + 'h04fff,
    VSCLICCFG_START[21] + 'h04fff,
    VSCLICCFG_START[22] + 'h04fff,
    VSCLICCFG_START[23] + 'h04fff,
    VSCLICCFG_START[24] + 'h04fff,
    VSCLICCFG_START[25] + 'h04fff,
    VSCLICCFG_START[26] + 'h04fff,
    VSCLICCFG_START[27] + 'h04fff,
    VSCLICCFG_START[28] + 'h04fff,
    VSCLICCFG_START[29] + 'h04fff,
    VSCLICCFG_START[30] + 'h04fff,
    VSCLICCFG_START[31] + 'h04fff,
    VSCLICCFG_START[32] + 'h04fff,
    VSCLICCFG_START[33] + 'h04fff,
    VSCLICCFG_START[34] + 'h04fff,
    VSCLICCFG_START[35] + 'h04fff,
    VSCLICCFG_START[36] + 'h04fff,
    VSCLICCFG_START[37] + 'h04fff,
    VSCLICCFG_START[38] + 'h04fff,
    VSCLICCFG_START[39] + 'h04fff,
    VSCLICCFG_START[40] + 'h04fff,
    VSCLICCFG_START[41] + 'h04fff,
    VSCLICCFG_START[42] + 'h04fff,
    VSCLICCFG_START[43] + 'h04fff,
    VSCLICCFG_START[44] + 'h04fff,
    VSCLICCFG_START[45] + 'h04fff,
    VSCLICCFG_START[46] + 'h04fff,
    VSCLICCFG_START[47] + 'h04fff,
    VSCLICCFG_START[48] + 'h04fff,
    VSCLICCFG_START[49] + 'h04fff,
    VSCLICCFG_START[50] + 'h04fff,
    VSCLICCFG_START[51] + 'h04fff,
    VSCLICCFG_START[52] + 'h04fff,
    VSCLICCFG_START[53] + 'h04fff,
    VSCLICCFG_START[54] + 'h04fff,
    VSCLICCFG_START[55] + 'h04fff,
    VSCLICCFG_START[56] + 'h04fff,
    VSCLICCFG_START[57] + 'h04fff,
    VSCLICCFG_START[58] + 'h04fff,
    VSCLICCFG_START[59] + 'h04fff,
    VSCLICCFG_START[60] + 'h04fff,
    VSCLICCFG_START[61] + 'h04fff,
    VSCLICCFG_START[62] + 'h04fff,
    VSCLICCFG_START[63] + 'h04fff
  };

  // Hardware interfaces of the generated register blocks
  cliccfg_reg_pkg::cliccfg__out_t cliccfg_hwif_out;

  clicint_reg_pkg::clicint__in_t  clicint_hwif_in  [N_SOURCE];
  clicint_reg_pkg::clicint__out_t clicint_hwif_out [N_SOURCE];

  clicintv_reg_pkg::clicintv__out_t clicintv_hwif_out [N_INTV];

  clicvs_reg_pkg::clicvs__out_t clicvs_hwif_out [N_VS];

  logic [7:0] intctl [N_SOURCE];
  logic [7:0] irq_max;

  logic [1:0] intmode [N_SOURCE];
  logic [1:0] irq_mode;

  logic [VSID_W-1:0] vsid [N_SOURCE]; // Per-IRQ Virtual Supervisor (VS) ID
  logic              intv [N_SOURCE]; // Per-IRQ virtualization bit

  logic [VSPRIO_W-1:0] vsprio [MAX_VSCTXTS]; // Per-VS priority

  logic [N_SOURCE-1:0] le; // 0: level-sensitive 1: edge-sensitive
  logic [N_SOURCE-1:0] ip;
  logic [N_SOURCE-1:0] ie;
  logic [N_SOURCE-1:0] ip_sw; // sw-based edge-triggered interrupt
  logic [N_SOURCE-1:0] shv; // Handle per-irq SHV bits

  logic [N_SOURCE-1:0] claim;

  // Unpacked once here so the decoder below can keep working on flat signals.
  logic        psel, penable, pwrite;
  logic [2:0]  pprot;
  logic [31:0] pwdata;
  logic [3:0]  pstrb;
  logic        pready, pslverr;
  logic [31:0] prdata;

  assign psel    = apb_req_i.psel;
  assign penable = apb_req_i.penable;
  assign pwrite  = apb_req_i.pwrite;
  assign pprot   = apb_req_i.pprot;
  assign pwdata  = apb_req_i.pwdata;
  assign pstrb   = apb_req_i.pstrb;

  assign apb_rsp_o.pready  = pready;
  assign apb_rsp_o.prdata  = prdata;
  assign apb_rsp_o.pslverr = pslverr;

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
    .PrioWidth   (INTCTLBITS),
    .ModeWidth   (2),
    .VsidWidth   (VSID_W),
    .VsprioWidth (VSPRIO_W)
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
    .irq_kill_ack_i
  );

  ///////////////////////////////////////////////////
  //                 Bus fan-out                   //
  ///////////////////////////////////////////////////
  //
  // Every generated block is a leaf holding a single 32-bit register, so all of
  // them share one APB channel and are distinguished only by their select line.
  // The decoder below drives at most one select at a time and picks the
  // matching response.
  //
  // Two things are rewritten on the way down rather than being expressed in the
  // register description, because SystemRDL has no notion of which address
  // window an access arrived through:
  //   - CLICINT bit 23 is forced low outside the M-mode window, so a line
  //     cannot be promoted to M-mode from a less privileged window.
  //   - CLICINTV lanes belonging to a line above S-mode are zeroed on write and
  //     read back as zero.
  //
  // The permission inputs (intmode, intv, vsid) are software-writable only and
  // there is a single bus port, so they cannot change underneath a transfer
  // that is already in progress.

  // Leaves only ever see the two byte-offset bits; the register index is
  // resolved here into a one-hot select.
  logic [2:0] leaf_paddr;
  assign leaf_paddr = {1'b0, apb_req_i.paddr[1:0]};

  // cliccfg
  logic        cliccfg_psel;
  logic [31:0] cliccfg_prdata;
  logic        cliccfg_pready, cliccfg_pslverr;

  // clicint
  logic                        int_psel;
  logic [ADDR_W-1:0]           int_idx;
  logic                        int_idx_ok;
  logic [31:0]                 int_pwdata;
  logic [N_SOURCE-1:0]         int_psel_oh;
  logic [N_SOURCE-1:0][31:0]   int_prdata;
  logic [N_SOURCE-1:0]         int_pready;
  logic [N_SOURCE-1:0]         int_pslverr;
  logic [31:0]                 int_sel_prdata;
  logic                        int_sel_pready, int_sel_pslverr;

  // clicintv
  logic                        v_psel;
  logic [ADDR_W-1:0]           v_idx;
  logic                        v_idx_ok;
  logic [31:0]                 v_pwdata;
  logic [3:0]                  v_lane_ok; // lane belongs to an existing S-mode-or-below line
  logic [N_INTV-1:0]           v_psel_oh;
  logic [N_INTV-1:0][31:0]     v_prdata;
  logic [N_INTV-1:0]           v_pready;
  logic [N_INTV-1:0]           v_pslverr;
  logic [31:0]                 v_sel_prdata;
  logic                        v_sel_pready, v_sel_pslverr;

  // clicvs
  logic                        vs_psel;
  logic [ADDR_W-1:0]           vs_idx;
  logic                        vs_idx_ok;
  logic [N_VS-1:0]             vs_psel_oh;
  logic [N_VS-1:0][31:0]       vs_prdata;
  logic [N_VS-1:0]             vs_pready;
  logic [N_VS-1:0]             vs_pslverr;
  logic [31:0]                 vs_sel_prdata;
  logic                        vs_sel_pready, vs_sel_pslverr;

  // configuration register, aliased into the M-mode and S-mode windows
  // 0x0000 (machine mode) and 0x8000 (supervisor mode)
  cliccfg_reg i_cliccfg_reg (
    .clk           (clk_i),
    .arst_n        (rst_ni),

    .s_apb_psel    (cliccfg_psel),
    .s_apb_penable (penable),
    .s_apb_pwrite  (pwrite),
    .s_apb_pprot   (pprot),
    .s_apb_paddr   (leaf_paddr),
    .s_apb_pwdata  (pwdata),
    .s_apb_pstrb   (pstrb),
    .s_apb_pready  (cliccfg_pready),
    .s_apb_prdata  (cliccfg_prdata),
    .s_apb_pslverr (cliccfg_pslverr),

    .hwif_out      (cliccfg_hwif_out)
  );

  // interrupt control and status registers (per interrupt line)
  // 0x1000 - 0x4fff (machine mode)
  assign int_idx_ok = (int_idx < N_SOURCE);

  always_comb begin
    int_psel_oh = '0;
    if (int_psel && int_idx_ok) int_psel_oh[int_idx] = 1'b1;
  end

  assign int_sel_prdata  = int_idx_ok ? int_prdata[int_idx]  : 32'h0;
  assign int_sel_pready  = int_idx_ok ? int_pready[int_idx]  : 1'b1;
  assign int_sel_pslverr = int_idx_ok ? int_pslverr[int_idx] : 1'b0;

  for (genvar i = 0; i < N_SOURCE; i++) begin : gen_clic_int
    clicint_reg i_clicint_reg (
      .clk           (clk_i),
      .arst_n        (rst_ni),

      .s_apb_psel    (int_psel_oh[i]),
      .s_apb_penable (penable),
      .s_apb_pwrite  (pwrite),
      .s_apb_pprot   (pprot),
      .s_apb_paddr   (leaf_paddr),
      .s_apb_pwdata  (int_pwdata),
      .s_apb_pstrb   (pstrb),
      .s_apb_pready  (int_pready[i]),
      .s_apb_prdata  (int_prdata[i]),
      .s_apb_pslverr (int_pslverr[i]),

      .hwif_in       (clicint_hwif_in[i]),
      .hwif_out      (clicint_hwif_out[i])
    );
  end

  // interrupt virtualization registers (one per four interrupt lines)
  // 0xd000 - 0xdfff (supervisor mode)
  if (VSCLIC) begin : gen_clic_intv

    assign v_idx_ok = (v_idx < N_INTV);

    always_comb begin
      v_psel_oh = '0;
      if (v_psel && v_idx_ok) v_psel_oh[v_idx] = 1'b1;
    end

    assign v_sel_prdata  = v_idx_ok ? v_prdata[v_idx]  : 32'h0;
    assign v_sel_pready  = v_idx_ok ? v_pready[v_idx]  : 1'b1;
    assign v_sel_pslverr = v_idx_ok ? v_pslverr[v_idx] : 1'b0;

    for (genvar i = 0; i < N_INTV; i++) begin : gen_clic_intv_blk
      clicintv_reg i_clicintv_reg (
        .clk           (clk_i),
        .arst_n        (rst_ni),

        .s_apb_psel    (v_psel_oh[i]),
        .s_apb_penable (penable),
        .s_apb_pwrite  (pwrite),
        .s_apb_pprot   (pprot),
        .s_apb_paddr   (leaf_paddr),
        .s_apb_pwdata  (v_pwdata),
        .s_apb_pstrb   (pstrb),
        .s_apb_pready  (v_pready[i]),
        .s_apb_prdata  (v_prdata[i]),
        .s_apb_pslverr (v_pslverr[i]),

        .hwif_out      (clicintv_hwif_out[i])
      );
    end

    // VS priority registers (one per four VS contexts)
    // 0xe000 - 0xefff (supervisor mode)
    if (VSPRIO) begin : gen_clic_vs

      assign vs_idx_ok = (vs_idx < N_VS);

      always_comb begin
        vs_psel_oh = '0;
        if (vs_psel && vs_idx_ok) vs_psel_oh[vs_idx] = 1'b1;
      end

      assign vs_sel_prdata  = vs_idx_ok ? vs_prdata[vs_idx]  : 32'h0;
      assign vs_sel_pready  = vs_idx_ok ? vs_pready[vs_idx]  : 1'b1;
      assign vs_sel_pslverr = vs_idx_ok ? vs_pslverr[vs_idx] : 1'b0;

      for (genvar i = 0; i < N_VS; i++) begin : gen_clic_vs_blk
        clicvs_reg i_clicvs_reg (
          .clk           (clk_i),
          .arst_n        (rst_ni),

          .s_apb_psel    (vs_psel_oh[i]),
          .s_apb_penable (penable),
          .s_apb_pwrite  (pwrite),
          .s_apb_pprot   (pprot),
          .s_apb_paddr   (leaf_paddr),
          .s_apb_pwdata  (pwdata),
          .s_apb_pstrb   (pstrb),
          .s_apb_pready  (vs_pready[i]),
          .s_apb_prdata  (vs_prdata[i]),
          .s_apb_pslverr (vs_pslverr[i]),

          .hwif_out      (clicvs_hwif_out[i])
        );
      end

    end else begin : gen_no_clic_vs
      for (genvar i = 0; i < N_VS; i++) begin : gen_tie_vs
        assign clicvs_hwif_out[i] = '{default: '0};
      end
      assign vs_psel_oh     = '0;
      assign vs_prdata      = '0;
      assign vs_pready      = '0;
      assign vs_pslverr     = '0;
      assign vs_idx_ok      = 1'b0;
      assign vs_sel_prdata  = 32'h0;
      assign vs_sel_pready  = 1'b1;
      assign vs_sel_pslverr = 1'b0;
    end

  end else begin : gen_no_clic_intv
    for (genvar i = 0; i < N_INTV; i++) begin : gen_tie_intv
      assign clicintv_hwif_out[i] = '{default: '0};
    end
    for (genvar i = 0; i < N_VS; i++) begin : gen_tie_vs
      assign clicvs_hwif_out[i] = '{default: '0};
    end
    assign v_psel_oh      = '0;
    assign v_prdata       = '0;
    assign v_pready       = '0;
    assign v_pslverr      = '0;
    assign v_idx_ok       = 1'b0;
    assign v_sel_prdata   = 32'h0;
    assign v_sel_pready   = 1'b1;
    assign v_sel_pslverr  = 1'b0;

    assign vs_psel_oh     = '0;
    assign vs_prdata      = '0;
    assign vs_pready      = '0;
    assign vs_pslverr     = '0;
    assign vs_idx_ok      = 1'b0;
    assign vs_sel_prdata  = 32'h0;
    assign vs_sel_pready  = 1'b1;
    assign vs_sel_pslverr = 1'b0;
  end

  ///////////////////////////////////////////////////
  //         Top level address decoding            //
  ///////////////////////////////////////////////////

  // Helper signal used to store intermediate address
  logic [ADDR_W-1:0] addr_tmp;

  // The access decoded to a window but is not permitted or not implemented:
  // terminate it immediately, returning zeros without an error.
  logic void_access;

  always_comb begin : clic_addr_decode
    // Index of the interrupt line an access refers to. Every window is larger
    // than the number of lines behind it, so the index is range-checked before
    // it reaches intmode/intv/vsid: without the clamp an access to the unused
    // top of a window would read those arrays out of bounds.
    automatic logic [ADDR_W-1:0] line_idx;
    automatic logic              line_ok;
    automatic logic [ADDR_W-1:0] line_idx_safe;

    line_idx      = '0;
    line_ok       = 1'b0;
    line_idx_safe = '0;

    cliccfg_psel  = 1'b0;

    int_psel    = 1'b0;
    int_idx     = '0;
    int_pwdata  = pwdata;

    v_psel      = 1'b0;
    v_idx       = '0;
    v_pwdata    = pwdata;
    v_lane_ok   = 4'b1111;

    vs_psel     = 1'b0;
    vs_idx      = '0;

    void_access = 1'b0;

    addr_tmp    = '0;

    unique case(apb_req_i.paddr[ADDR_W-1:0]) inside
      MCLICCFG_START: begin
        cliccfg_psel = psel;
      end
      [MCLICINT_START:MCLICINT_END]: begin
        addr_tmp = apb_req_i.paddr[ADDR_W-1:0] - MCLICINT_START;
        int_psel = psel;
        int_idx  = {2'b0, addr_tmp[ADDR_W-1:2]};
      end
      SCLICCFG_START: begin
        if (SSCLIC) begin
          cliccfg_psel = psel;
        end else begin
          void_access = 1'b1;
        end
      end
      [SCLICINT_START:SCLICINT_END]: begin
        if (SSCLIC) begin
          addr_tmp      = apb_req_i.paddr[ADDR_W-1:0] - SCLICINT_START;
          line_idx      = {2'b0, addr_tmp[ADDR_W-1:2]};
          line_ok       = (line_idx < N_SOURCE);
          line_idx_safe = line_ok ? line_idx : '0;
          // check whether the irq we want to access is s-mode or lower
          if (line_ok && (intmode[line_idx_safe] <= S_MODE)) begin
            int_psel = psel;
            int_idx  = line_idx;
            // Prevent setting interrupt mode to m-mode
            int_pwdata[23] = 1'b0;
          end else begin
            void_access = 1'b1;
          end
        end else begin
          void_access = 1'b1;
        end
      end
      [SCLICINTV_START:SCLICINTV_END]: begin
        if (VSCLIC) begin
          addr_tmp = apb_req_i.paddr[ADDR_W-1:0] - SCLICINTV_START;
          v_psel   = psel;
          v_idx    = {2'b0, addr_tmp[ADDR_W-1:2]};
          // One lane per interrupt line. A lane whose line does not exist, or
          // is configured above S-mode, has no virtualization state: it is
          // written as zero and reads back as zero.
          for (int unsigned k = 0; k < 4; k++) begin
            line_idx      = ({2'b0, addr_tmp[ADDR_W-1:2]} << 2) + k[ADDR_W-1:0];
            line_ok       = (line_idx < N_SOURCE);
            line_idx_safe = line_ok ? line_idx : '0;
            v_lane_ok[k]  = line_ok && (intmode[line_idx_safe] <= S_MODE);
            if (!v_lane_ok[k]) v_pwdata[8*k +: 8] = 8'b0;
          end
        end else begin
          void_access = 1'b1;
        end
      end
      [VSCLICPRIO_START:VSCLICPRIO_END]: begin
        if (VSCLIC && VSPRIO) begin
          addr_tmp = apb_req_i.paddr[ADDR_W-1:0] - VSCLICPRIO_START;
          vs_psel  = psel;
          vs_idx   = {2'b0, addr_tmp[ADDR_W-1:2]};
        end else begin
          void_access = 1'b1;
        end
      end
      default: begin
        void_access = 1'b1;
      end
    endcase // unique case (apb_req_i.paddr)

    // Match VS address space
    if (VSCLIC) begin
      for (int i = 0; i < N_VSCTXTS; i++) begin
        if (apb_req_i.paddr[ADDR_W-1:0] == VSCLICCFG_START[i]) begin
          void_access = 1'b1;
        end else if (VSCLICINT_START[i] <= apb_req_i.paddr[ADDR_W-1:0] &&
                     apb_req_i.paddr[ADDR_W-1:0] <= VSCLICINT_END[i]) begin
          addr_tmp      = apb_req_i.paddr[ADDR_W-1:0] - VSCLICINT_START[i];
          line_idx      = {2'b0, addr_tmp[ADDR_W-1:2]};
          line_ok       = (line_idx < N_SOURCE);
          line_idx_safe = line_ok ? line_idx : '0;
          // check whether the irq we want to access is s-mode and its v bit is
          // set and the VSID corresponds
          if (line_ok                                &&
              (intmode[line_idx_safe] == S_MODE)     &&
              intv[line_idx_safe]                    &&
              (vsid[line_idx_safe] == VSID_W'(i + 1))) begin
            int_psel = psel;
            int_idx  = line_idx;
            // Prevent setting interrupt mode to m-mode
            int_pwdata[23] = 1'b0;
            void_access    = 1'b0;
          end else begin
            void_access = 1'b1;
          end
        end
      end
    end
  end

  // Response mux: at most one group is selected at a time.
  always_comb begin : clic_rsp_mux
    prdata  = 32'h0;
    pready  = 1'b1;
    pslverr = 1'b0;

    if (void_access) begin
      // inaccesible (all zero)
      prdata  = 32'h0;
      pready  = 1'b1;
      pslverr = 1'b0;
    end else if (cliccfg_psel) begin
      prdata  = cliccfg_prdata;
      pready  = cliccfg_pready;
      pslverr = cliccfg_pslverr;
    end else if (int_psel) begin
      prdata  = int_sel_prdata;
      pready  = int_sel_pready;
      pslverr = int_sel_pslverr;
    end else if (v_psel) begin
      prdata  = v_sel_prdata;
      pready  = v_sel_pready;
      pslverr = v_sel_pslverr;
      // Lanes without virtualization state read back as zero.
      for (int unsigned k = 0; k < 4; k++) begin
        if (!v_lane_ok[k]) prdata[8*k +: 8] = 8'b0;
      end
    end else if (vs_psel) begin
      prdata  = vs_sel_prdata;
      pready  = vs_sel_pready;
      pslverr = vs_sel_pslverr;
    end
  end

  // adapter
  clic_reg_adapter #(
    .N_SOURCE    (N_SOURCE),
    .INTCTLBITS  (INTCTLBITS),
    .VsidWidth   (VSID_W),
    .VsprioWidth (VSPRIO_W)
  ) i_clic_reg_adapter (
    .clk_i,
    .rst_ni,

    .cliccfg_hwif_out,

    .clicint_hwif_out,
    .clicint_hwif_in,

    .clicintv_hwif_out,

    .clicvs_hwif_out,

    .intctl_o  (intctl),
    .intmode_o (intmode),
    .shv_o     (shv),
    .vsid_o    (vsid),
    .intv_o    (intv),
    .vsprio_o  (vsprio),
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
    if (cliccfg_hwif_out.cliccfg.mnlbits.value <= INTCTLBITS)
      mnlbits = cliccfg_hwif_out.cliccfg.mnlbits.value;
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
      nmbits[0] = cliccfg_hwif_out.cliccfg.nmbits.value[0];

    if ((VSCLIC || SSCLIC) && USCLIC)
      nmbits[1] = cliccfg_hwif_out.cliccfg.nmbits.value[1];
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
