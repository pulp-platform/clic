// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSES/SHL-0.51.txt for details.
// SPDX-License-Identifier: SHL-0.51

// Flattens the per-block PeakRDL hardware interfaces into the per-source
// arrays consumed by clic_gateway and clic_target.

module clic_reg_adapter
  import clic_pkg::*;
  import cf_math_pkg::*;
#(
  parameter int N_SOURCE = 32,
  parameter int INTCTLBITS = 8,
  parameter int unsigned VsidWidth = 6,
  parameter int unsigned VsprioWidth = 8
)(
  input logic                 clk_i,
  input logic                 rst_ni,

  input  cliccfg_reg_pkg::cliccfg__out_t cliccfg_hwif_out,

  input  clicint_reg_pkg::clicint__out_t clicint_hwif_out [N_SOURCE],
  output clicint_reg_pkg::clicint__in_t  clicint_hwif_in  [N_SOURCE],

  input  clicintv_reg_pkg::clicintv__out_t clicintv_hwif_out [ceil_div(N_SOURCE, 4)],

  input  clicvs_reg_pkg::clicvs__out_t clicvs_hwif_out [MAX_VSCTXTS/4],

  output logic [7:0]              intctl_o  [N_SOURCE],
  output logic [1:0]              intmode_o [N_SOURCE],
  output logic [VsidWidth-1:0]    vsid_o    [N_SOURCE], // interrupt VS id
  output logic                    intv_o    [N_SOURCE], // interrupt virtualization
  output logic [VsprioWidth-1:0]  vsprio_o  [MAX_VSCTXTS], // VS priority
  output logic [N_SOURCE-1:0] shv_o,
  output logic [N_SOURCE-1:0] ip_sw_o,
  output logic [N_SOURCE-1:0] ie_o,
  output logic [N_SOURCE-1:0] le_o,

  input logic [N_SOURCE-1:0]  ip_i
);

  localparam int unsigned N_SOURCE_ALIGNED = rounddown(N_SOURCE, 4);

  // We only support positive edge triggered and positive level triggered
  // interrupts atm. Either we hardware the trig.q[1] bit correctly or we
  // implement all modes
  //
  // `we` is tied high so the gateway drives pending every cycle. A software
  // write to IP in the same cycle still wins: the register block resolves the
  // conflict with `precedence = sw` (see src/gen/clicint.rdl), which is what
  // makes a software-triggered interrupt possible.
  for (genvar i = 0; i < N_SOURCE; i++) begin : gen_reghw
    assign intctl_o[i] = clicint_hwif_out[i].clicint.ctl.value;
    assign intmode_o[i] = clicint_hwif_out[i].clicint.attr_mode.value;
    assign shv_o[i] = clicint_hwif_out[i].clicint.attr_shv.value;
    assign ip_sw_o[i] = clicint_hwif_out[i].clicint.ip.value;
    assign ie_o[i] = clicint_hwif_out[i].clicint.ie.value;
    assign clicint_hwif_in[i].clicint.ip.we   = 1'b1; // Always write
    assign clicint_hwif_in[i].clicint.ip.next = ip_i[i];
    assign le_o[i] = clicint_hwif_out[i].clicint.attr_trig.value[0];
  end

  for (genvar i = 0; i < rounddown(N_SOURCE, 4); i = i + 4) begin : gen_reghw_v
    assign vsid_o[i+0] = clicintv_hwif_out[i/4].clicintv.vsid0.value;
    assign intv_o[i+0] = clicintv_hwif_out[i/4].clicintv.v0.value;
    assign vsid_o[i+1] = clicintv_hwif_out[i/4].clicintv.vsid1.value;
    assign intv_o[i+1] = clicintv_hwif_out[i/4].clicintv.v1.value;
    assign vsid_o[i+2] = clicintv_hwif_out[i/4].clicintv.vsid2.value;
    assign intv_o[i+2] = clicintv_hwif_out[i/4].clicintv.v2.value;
    assign vsid_o[i+3] = clicintv_hwif_out[i/4].clicintv.vsid3.value;
    assign intv_o[i+3] = clicintv_hwif_out[i/4].clicintv.v3.value;
  end

  if ((N_SOURCE%4) > 0) begin : gen_reghw_v_rem0
    assign vsid_o[N_SOURCE_ALIGNED+0] = clicintv_hwif_out[N_SOURCE/4].clicintv.vsid0.value;
    assign intv_o[N_SOURCE_ALIGNED+0] = clicintv_hwif_out[N_SOURCE/4].clicintv.v0.value;
  end

  if ((N_SOURCE%4) > 1) begin : gen_reghw_v_rem1
    assign vsid_o[N_SOURCE_ALIGNED+1] = clicintv_hwif_out[N_SOURCE/4].clicintv.vsid1.value;
    assign intv_o[N_SOURCE_ALIGNED+1] = clicintv_hwif_out[N_SOURCE/4].clicintv.v1.value;
  end

  if ((N_SOURCE%4) > 2) begin : gen_reghw_v_rem2
    assign vsid_o[N_SOURCE_ALIGNED+2] = clicintv_hwif_out[N_SOURCE/4].clicintv.vsid2.value;
    assign intv_o[N_SOURCE_ALIGNED+2] = clicintv_hwif_out[N_SOURCE/4].clicintv.v2.value;
  end

  for (genvar i = 0; i < MAX_VSCTXTS; i = i + 4) begin : gen_reghw_vs
    assign vsprio_o[i+0] = clicvs_hwif_out[i/4].vsprio.prio0.value;
    assign vsprio_o[i+1] = clicvs_hwif_out[i/4].vsprio.prio1.value;
    assign vsprio_o[i+2] = clicvs_hwif_out[i/4].vsprio.prio2.value;
    assign vsprio_o[i+3] = clicvs_hwif_out[i/4].vsprio.prio3.value;
  end

endmodule // clic_reg_adapter
