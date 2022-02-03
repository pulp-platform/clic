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

module clic_reg_top #(
    parameter type reg_req_t = logic,
    parameter type reg_rsp_t = logic,
    parameter int AW = 13
) (
  input clk_i,
  input rst_ni,
  input  reg_req_t reg_req_i,
  output reg_rsp_t reg_rsp_o,
  // To HW
  output clic_reg_pkg::clic_reg2hw_t reg2hw, // Write
  input  clic_reg_pkg::clic_hw2reg_t hw2reg, // Read


  // Config
  input devmode_i // If 1, explicit error return for unmapped register access
);

  import clic_reg_pkg::* ;

  localparam int DW = 32;
  localparam int DBW = DW/8;                    // Byte Width

  // register signals
  logic           reg_we;
  logic           reg_re;
  logic [AW-1:0]  reg_addr;
  logic [DW-1:0]  reg_wdata;
  logic [DBW-1:0] reg_be;
  logic [DW-1:0]  reg_rdata;
  logic           reg_error;

  logic          addrmiss, wr_err;

  logic [DW-1:0] reg_rdata_next;

  // Below register interface can be changed
  reg_req_t  reg_intf_req;
  reg_rsp_t  reg_intf_rsp;


  assign reg_intf_req = reg_req_i;
  assign reg_rsp_o = reg_intf_rsp;


  assign reg_we = reg_intf_req.valid & reg_intf_req.write;
  assign reg_re = reg_intf_req.valid & ~reg_intf_req.write;
  assign reg_addr = reg_intf_req.addr;
  assign reg_wdata = reg_intf_req.wdata;
  assign reg_be = reg_intf_req.wstrb;
  assign reg_intf_rsp.rdata = reg_rdata;
  assign reg_intf_rsp.error = reg_error;
  assign reg_intf_rsp.ready = 1'b1;

  assign reg_rdata = reg_rdata_next ;
  assign reg_error = (devmode_i & addrmiss) | wr_err;


  // Define SW related signals
  // Format: <reg>_<field>_{wd|we|qs}
  //        or <reg>_{wd|we|qs} if field == 1 or 0
  logic cliccfg_nvbits_qs;
  logic cliccfg_nvbits_wd;
  logic cliccfg_nvbits_we;
  logic [3:0] cliccfg_nlbits_qs;
  logic [3:0] cliccfg_nlbits_wd;
  logic cliccfg_nlbits_we;
  logic [1:0] cliccfg_nmbits_qs;
  logic [1:0] cliccfg_nmbits_wd;
  logic cliccfg_nmbits_we;
  logic [12:0] clicinfo_num_interrupt_qs;
  logic [7:0] clicinfo_version_qs;
  logic [3:0] clicinfo_clicintctlbits_qs;
  logic [5:0] clicinfo_num_trigger_qs;
  logic [NumSrc-1:0] clicintip_qs;
  logic [NumSrc-1:0] clicintip_wd;
  logic [NumSrc-1:0] clicintip_we;
  logic [NumSrc-1:0] clicintie_qs;
  logic [NumSrc-1:0] clicintie_wd;
  logic [NumSrc-1:0] clicintie_we;
  logic [NumSrc-1:0] clicintattr_shv_qs;
  logic [NumSrc-1:0] clicintattr_shv_wd;
  logic [NumSrc-1:0] clicintattr_shv_we;
  logic [NumSrc-1:0][1:0] clicintattr_trig_qs;
  logic [NumSrc-1:0][1:0] clicintattr_trig_wd;
  logic [NumSrc-1:0] clicintattr_trig_we;
  logic [NumSrc-1:0][1:0] clicintattr_mode_qs;
  logic [NumSrc-1:0][1:0] clicintattr_mode_wd;
  logic [NumSrc-1:0] clicintattr_mode_we;
  logic [NumSrc-1:0][7:0] clicintctrl_qs;
  logic [NumSrc-1:0][7:0] clicintctrl_wd;
  logic [NumSrc-1:0] clicintctrl_we;

  // Register instances
  // R[cliccfg]: V(False)

  //   F[nvbits]: 0:0
  prim_subreg #(
    .DW      (1),
    .SWACCESS("RW"),
    .RESVAL  (1'h0)
  ) u_cliccfg_nvbits (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    // from register interface
    .we     (cliccfg_nvbits_we),
    .wd     (cliccfg_nvbits_wd),

    // from internal hardware
    .de     (1'b0),
    .d      ('0  ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.cliccfg.nvbits.q ),

    // to register interface (read)
    .qs     (cliccfg_nvbits_qs)
  );


  //   F[nlbits]: 4:1
  prim_subreg #(
    .DW      (4),
    .SWACCESS("RW"),
    .RESVAL  (4'h0)
  ) u_cliccfg_nlbits (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    // from register interface
    .we     (cliccfg_nlbits_we),
    .wd     (cliccfg_nlbits_wd),

    // from internal hardware
    .de     (1'b0),
    .d      ('0  ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.cliccfg.nlbits.q ),

    // to register interface (read)
    .qs     (cliccfg_nlbits_qs)
  );


  //   F[nmbits]: 6:5
  prim_subreg #(
    .DW      (2),
    .SWACCESS("RW"),
    .RESVAL  (2'h0)
  ) u_cliccfg_nmbits (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    // from register interface
    .we     (cliccfg_nmbits_we),
    .wd     (cliccfg_nmbits_wd),

    // from internal hardware
    .de     (1'b0),
    .d      ('0  ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.cliccfg.nmbits.q ),

    // to register interface (read)
    .qs     (cliccfg_nmbits_qs)
  );


  // R[clicinfo]: V(False)

  //   F[num_interrupt]: 12:0
  prim_subreg #(
    .DW      (13),
    .SWACCESS("RO"),
    .RESVAL  (13'h0)
  ) u_clicinfo_num_interrupt (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    .we     (1'b0),
    .wd     ('0  ),

    // from internal hardware
    .de     (1'b0),
    .d      ('0  ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.clicinfo.num_interrupt.q ),

    // to register interface (read)
    .qs     (clicinfo_num_interrupt_qs)
  );


  //   F[version]: 20:13
  prim_subreg #(
    .DW      (8),
    .SWACCESS("RO"),
    .RESVAL  (8'h0)
  ) u_clicinfo_version (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    .we     (1'b0),
    .wd     ('0  ),

    // from internal hardware
    .de     (1'b0),
    .d      ('0  ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.clicinfo.version.q ),

    // to register interface (read)
    .qs     (clicinfo_version_qs)
  );


  //   F[clicintctlbits]: 24:21
  prim_subreg #(
    .DW      (4),
    .SWACCESS("RO"),
    .RESVAL  (4'h0)
  ) u_clicinfo_clicintctlbits (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    .we     (1'b0),
    .wd     ('0  ),

    // from internal hardware
    .de     (1'b0),
    .d      ('0  ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.clicinfo.clicintctlbits.q ),

    // to register interface (read)
    .qs     (clicinfo_clicintctlbits_qs)
  );


  //   F[num_trigger]: 30:25
  prim_subreg #(
    .DW      (6),
    .SWACCESS("RO"),
    .RESVAL  (6'h0)
  ) u_clicinfo_num_trigger (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    .we     (1'b0),
    .wd     ('0  ),

    // from internal hardware
    .de     (1'b0),
    .d      ('0  ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.clicinfo.num_trigger.q ),

    // to register interface (read)
    .qs     (clicinfo_num_trigger_qs)
  );



  for (genvar i = 0; i < NumSrc; i++) begin : gen_clicint
    // R[clicintip0]: V(False)

    prim_subreg #(
      .DW      (1),
      .SWACCESS("RW"),
      .RESVAL  (1'h0)
    ) u_clicintip (
      .clk_i   (clk_i    ),
      .rst_ni  (rst_ni  ),

      // from register interface
      .we     (clicintip_we[i]),
      .wd     (clicintip_wd[i]),

      // from internal hardware
      .de     (hw2reg.clicintip[i].de),
      .d      (hw2reg.clicintip[i].d ),

      // to internal hardware
      .qe     (),
      .q      (reg2hw.clicintip[i].q ),

      // to register interface (read)
      .qs     (clicintip_qs[i])
    );

    // R[clicintie0]: V(False)

    prim_subreg #(
      .DW      (1),
      .SWACCESS("RW"),
      .RESVAL  (1'h0)
    ) u_clicintie (
      .clk_i   (clk_i    ),
      .rst_ni  (rst_ni  ),

      // from register interface
      .we     (clicintie_we[i]),
      .wd     (clicintie_wd[i]),

      // from internal hardware
      .de     (1'b0),
      .d      ('0  ),

      // to internal hardware
      .qe     (),
      .q      (reg2hw.clicintie[i].q ),

      // to register interface (read)
      .qs     (clicintie_qs[i])
    );

    // R[clicintattr0]: V(False)

    //   F[shv]: 0:0
    prim_subreg #(
      .DW      (1),
      .SWACCESS("RW"),
      .RESVAL  (1'h0)
    ) u_clicintattr0_shv (
      .clk_i   (clk_i    ),
      .rst_ni  (rst_ni  ),

      // from register interface
      .we     (clicintattr_shv_we[i]),
      .wd     (clicintattr_shv_wd[i]),

      // from internal hardware
      .de     (1'b0),
      .d      ('0  ),

      // to internal hardware
      .qe     (),
      .q      (reg2hw.clicintattr[i].shv.q ),

      // to register interface (read)
      .qs     (clicintattr_shv_qs[i])
    );

    //   F[trig]: 2:1
    prim_subreg #(
      .DW      (2),
      .SWACCESS("RW"),
      .RESVAL  (2'h0)
    ) u_clicintattr_trig (
      .clk_i   (clk_i    ),
      .rst_ni  (rst_ni  ),

      // from register interface
      .we     (clicintattr_trig_we[i]),
      .wd     (clicintattr_trig_wd[i]),

      // from internal hardware
      .de     (1'b0),
      .d      ('0  ),

      // to internal hardware
      .qe     (),
      .q      (reg2hw.clicintattr[i].trig.q ),

      // to register interface (read)
      .qs     (clicintattr_trig_qs[i])
    );

    //   F[mode]: 7:6
    prim_subreg #(
      .DW      (2),
      .SWACCESS("RW"),
      .RESVAL  (2'h0)
    ) u_clicintattr_mode (
      .clk_i   (clk_i    ),
      .rst_ni  (rst_ni  ),

      // from register interface
      .we     (clicintattr_mode_we[i]),
      .wd     (clicintattr_mode_wd[i]),

      // from internal hardware
      .de     (1'b0),
      .d      ('0  ),

      // to internal hardware
      .qe     (),
      .q      (reg2hw.clicintattr[i].mode.q ),

      // to register interface (read)
      .qs     (clicintattr_mode_qs[i])
    );

    // R[clicintctrl0]: V(False)

    prim_subreg #(
      .DW      (8),
      .SWACCESS("RW"),
      .RESVAL  (8'h0)
    ) u_clicintctrl (
      .clk_i   (clk_i    ),
      .rst_ni  (rst_ni  ),

      // from register interface
      .we     (clicintctrl_we[i]),
      .wd     (clicintctrl_wd[i]),

      // from internal hardware
      .de     (1'b0),
      .d      ('0  ),

      // to internal hardware
      .qe     (),
      .q      (reg2hw.clicintctrl[i].q ),

      // to register interface (read)
      .qs     (clicintctrl_qs[i])
    );

  end


  logic [1:0] addr_hit_cfg;

  always_comb begin
    addr_hit_cfg = '0;

    // CLIC_CLICCFG
    // CLIC_CLICINFO
    addr_hit_cfg[0] = (reg_addr == CLIC_CLICCFG_OFFSET);
    addr_hit_cfg[1] = (reg_addr == CLIC_CLICINFO_OFFSET);
  end

  logic [4*NumSrc-1:0] addr_hit_int;

  always_comb begin
    addr_hit_int = '0;

    // CLIC_CLICINTIP
    // CLIC_CLICINTIE
    // CLIC_CLICINTATTR
    // CLIC_CLICINTCTRL
    if (reg_addr[12] == 1'h1)
      addr_hit_int[reg_addr[11:2]] = 1'b1;
  end

  assign addrmiss = (reg_re || reg_we) ? ~|{addr_hit_cfg, addr_hit_int} : 1'b0 ;
  assign wr_err = 1'b0;
  // // // Check sub-word write is permitted
  // always_comb begin
  //   wr_err = (reg_we &
  //            ((addr_hit[   0] & (|(CLIC_PERMIT[   0] & ~reg_be))) |
  //            (addr_hit[   1] & (|(CLIC_PERMIT[   1] & ~reg_be)))));
  // end

  assign cliccfg_nvbits_we = addr_hit_cfg[0] & reg_we & !reg_error;
  assign cliccfg_nvbits_wd = reg_wdata[0];

  assign cliccfg_nlbits_we = addr_hit_cfg[0] & reg_we & !reg_error;
  assign cliccfg_nlbits_wd = reg_wdata[4:1];

  assign cliccfg_nmbits_we = addr_hit_cfg[0] & reg_we & !reg_error;
  assign cliccfg_nmbits_wd = reg_wdata[6:5];


  for (genvar i = 0; i < NumSrc; i++) begin
    assign clicintip_we[i] = addr_hit_int[0 + 4*i] & reg_we & !reg_error;
    assign clicintip_wd[i] = reg_wdata[0];

    assign clicintie_we[i] = addr_hit_int[1 + 4*i] & reg_we & !reg_error;
    assign clicintie_wd[i] = reg_wdata[0];

    assign clicintattr_shv_we[i] = addr_hit_int[2 + 4*i] & reg_we & !reg_error;
    assign clicintattr_shv_wd[i] = reg_wdata[0];

    assign clicintattr_trig_we[i] = addr_hit_int[2 + 4*i] & reg_we & !reg_error;
    assign clicintattr_trig_wd[i] = reg_wdata[2:1];

    assign clicintattr_mode_we[i] = addr_hit_int[2 + 4*i] & reg_we & !reg_error;
    assign clicintattr_mode_wd[i] = reg_wdata[7:6];

    assign clicintctrl_we[i] = addr_hit_int[3 + 4*i] & reg_we & !reg_error;
    assign clicintctrl_wd[i] = reg_wdata[7:0];
  end

  // Read data return
  always_comb begin
    reg_rdata_next = '0;
    unique case (reg_addr) inside
      CLIC_CLICCFG_OFFSET: begin
        reg_rdata_next[0] = cliccfg_nvbits_qs;
        reg_rdata_next[4:1] = cliccfg_nlbits_qs;
        reg_rdata_next[6:5] = cliccfg_nmbits_qs;
      end

      CLIC_CLICINFO_OFFSET: begin
        reg_rdata_next[12:0] = clicinfo_num_interrupt_qs;
        reg_rdata_next[20:13] = clicinfo_version_qs;
        reg_rdata_next[24:21] = clicinfo_clicintctlbits_qs;
        reg_rdata_next[30:25] = clicinfo_num_trigger_qs;
      end

      CLIC_CLICINTIP_MASK: begin
        reg_rdata_next[0] = clicintip_qs[reg_addr[11:4]];
      end

      CLIC_CLICINTIE_MASK: begin
        reg_rdata_next[0] = clicintie_qs[reg_addr[11:4]];
      end

      CLIC_CLICINTATTR_MASK: begin
        reg_rdata_next[0] = clicintattr_shv_qs[reg_addr[11:4]];
        reg_rdata_next[2:1] = clicintattr_trig_qs[reg_addr[11:4]];
        reg_rdata_next[7:6] = clicintattr_mode_qs[reg_addr[11:4]];
      end

      CLIC_CLICINTCTRL_MASK: begin
        reg_rdata_next[7:0] = clicintctrl_qs[reg_addr[11:4]];
      end

      default: begin
        reg_rdata_next = '1;
      end
    endcase
  end

  // Unused signal tieoff

  // wdata / byte enable are not always fully used
  // add a blanket unused statement to handle lint waivers
  logic unused_wdata;
  logic unused_be;
  assign unused_wdata = ^reg_wdata;
  assign unused_be = ^reg_be;

  // Assertions for Register Interface
  `ASSERT(en2addrHit, (reg_we || reg_re) |-> $onehot0({addr_hit_cfg, addr_hit_int}))

endmodule
