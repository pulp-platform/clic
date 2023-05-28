// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Register Top module auto-generated by `reggen`


`include "common_cells/assertions.svh"

module clicint_reg_top #(
  parameter type reg_req_t = logic,
  parameter type reg_rsp_t = logic,
  parameter int AW = 2
) (
  input logic clk_i,
  input logic rst_ni,
  input  reg_req_t reg_req_i,
  output reg_rsp_t reg_rsp_o,
  // To HW
  output clicint_reg_pkg::clicint_reg2hw_t reg2hw, // Write
  input  clicint_reg_pkg::clicint_hw2reg_t hw2reg, // Read


  // Config
  input devmode_i // If 1, explicit error return for unmapped register access
);

  import clicint_reg_pkg::* ;

  localparam int DW = 32;
  localparam int DBW = DW/8;                    // Byte Width

  // register signals
  logic           reg_we;
  logic           reg_re;
  logic [BlockAw-1:0]  reg_addr;
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
  assign reg_addr = reg_intf_req.addr[BlockAw-1:0];
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
  logic clicint_ip_qs;
  logic clicint_ip_wd;
  logic clicint_ip_we;
  logic clicint_ie_qs;
  logic clicint_ie_wd;
  logic clicint_ie_we;
  logic clicint_attr_shv_qs;
  logic clicint_attr_shv_wd;
  logic clicint_attr_shv_we;
  logic [1:0] clicint_attr_trig_qs;
  logic [1:0] clicint_attr_trig_wd;
  logic clicint_attr_trig_we;
  logic [1:0] clicint_attr_mode_qs;
  logic [1:0] clicint_attr_mode_wd;
  logic clicint_attr_mode_we;
  logic [7:0] clicint_ctl_qs;
  logic [7:0] clicint_ctl_wd;
  logic clicint_ctl_we;

  // Register instances
  // R[clicint]: V(False)

  //   F[ip]: 0:0
  prim_subreg #(
    .DW      (1),
    .SWACCESS("RW"),
    .RESVAL  (1'h0)
  ) u_clicint_ip (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    // from register interface
    .we     (clicint_ip_we),
    .wd     (clicint_ip_wd),

    // from internal hardware
    .de     (hw2reg.clicint.ip.de),
    .d      (hw2reg.clicint.ip.d ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.clicint.ip.q ),

    // to register interface (read)
    .qs     (clicint_ip_qs)
  );


  //   F[ie]: 8:8
  prim_subreg #(
    .DW      (1),
    .SWACCESS("RW"),
    .RESVAL  (1'h0)
  ) u_clicint_ie (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    // from register interface
    .we     (clicint_ie_we),
    .wd     (clicint_ie_wd),

    // from internal hardware
    .de     (1'b0),
    .d      ('0  ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.clicint.ie.q ),

    // to register interface (read)
    .qs     (clicint_ie_qs)
  );


  //   F[attr_shv]: 16:16
  prim_subreg #(
    .DW      (1),
    .SWACCESS("RW"),
    .RESVAL  (1'h0)
  ) u_clicint_attr_shv (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    // from register interface
    .we     (clicint_attr_shv_we),
    .wd     (clicint_attr_shv_wd),

    // from internal hardware
    .de     (1'b0),
    .d      ('0  ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.clicint.attr_shv.q ),

    // to register interface (read)
    .qs     (clicint_attr_shv_qs)
  );


  //   F[attr_trig]: 18:17
  prim_subreg #(
    .DW      (2),
    .SWACCESS("RW"),
    .RESVAL  (2'h0)
  ) u_clicint_attr_trig (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    // from register interface
    .we     (clicint_attr_trig_we),
    .wd     (clicint_attr_trig_wd),

    // from internal hardware
    .de     (1'b0),
    .d      ('0  ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.clicint.attr_trig.q ),

    // to register interface (read)
    .qs     (clicint_attr_trig_qs)
  );


  //   F[attr_mode]: 23:22
  prim_subreg #(
    .DW      (2),
    .SWACCESS("RW"),
    .RESVAL  (2'h3)
  ) u_clicint_attr_mode (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    // from register interface
    .we     (clicint_attr_mode_we),
    .wd     (clicint_attr_mode_wd),

    // from internal hardware
    .de     (1'b0),
    .d      ('0  ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.clicint.attr_mode.q ),

    // to register interface (read)
    .qs     (clicint_attr_mode_qs)
  );


  //   F[ctl]: 31:24
  prim_subreg #(
    .DW      (8),
    .SWACCESS("RW"),
    .RESVAL  (8'h0)
  ) u_clicint_ctl (
    .clk_i   (clk_i    ),
    .rst_ni  (rst_ni  ),

    // from register interface
    .we     (clicint_ctl_we),
    .wd     (clicint_ctl_wd),

    // from internal hardware
    .de     (1'b0),
    .d      ('0  ),

    // to internal hardware
    .qe     (),
    .q      (reg2hw.clicint.ctl.q ),

    // to register interface (read)
    .qs     (clicint_ctl_qs)
  );




  logic [0:0] addr_hit;
  always_comb begin
    addr_hit = '0;
    addr_hit[0] = (reg_addr == CLICINT_CLICINT_OFFSET);
  end

  assign addrmiss = (reg_re || reg_we) ? ~|addr_hit : 1'b0 ;

  // Check sub-word write is permitted
  always_comb begin
    wr_err = (reg_we &
              ((addr_hit[0] & (|(CLICINT_PERMIT[0] & ~reg_be)))));
  end

  assign clicint_ip_we = addr_hit[0] & reg_we & !reg_error;
  assign clicint_ip_wd = reg_wdata[0];

  assign clicint_ie_we = addr_hit[0] & reg_we & !reg_error;
  assign clicint_ie_wd = reg_wdata[8];

  assign clicint_attr_shv_we = addr_hit[0] & reg_we & !reg_error;
  assign clicint_attr_shv_wd = reg_wdata[16];

  assign clicint_attr_trig_we = addr_hit[0] & reg_we & !reg_error;
  assign clicint_attr_trig_wd = reg_wdata[18:17];

  assign clicint_attr_mode_we = addr_hit[0] & reg_we & !reg_error;
  assign clicint_attr_mode_wd = reg_wdata[23:22];

  assign clicint_ctl_we = addr_hit[0] & reg_we & !reg_error;
  assign clicint_ctl_wd = reg_wdata[31:24];

  // Read data return
  always_comb begin
    reg_rdata_next = '0;
    unique case (1'b1)
      addr_hit[0]: begin
        reg_rdata_next[0] = clicint_ip_qs;
        reg_rdata_next[8] = clicint_ie_qs;
        reg_rdata_next[16] = clicint_attr_shv_qs;
        reg_rdata_next[18:17] = clicint_attr_trig_qs;
        reg_rdata_next[23:22] = clicint_attr_mode_qs;
        reg_rdata_next[31:24] = clicint_ctl_qs;
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
  `ASSERT(en2addrHit, (reg_we || reg_re) |-> $onehot0(addr_hit))

endmodule

module clicint_reg_top_intf
#(
  parameter int AW = 2,
  localparam int DW = 32
) (
  input logic clk_i,
  input logic rst_ni,
  REG_BUS.in  regbus_slave,
  // To HW
  output clicint_reg_pkg::clicint_reg2hw_t reg2hw, // Write
  input  clicint_reg_pkg::clicint_hw2reg_t hw2reg, // Read
  // Config
  input devmode_i // If 1, explicit error return for unmapped register access
);
 localparam int unsigned STRB_WIDTH = DW/8;

`include "register_interface/typedef.svh"
`include "register_interface/assign.svh"

  // Define structs for reg_bus
  typedef logic [AW-1:0] addr_t;
  typedef logic [DW-1:0] data_t;
  typedef logic [STRB_WIDTH-1:0] strb_t;
  `REG_BUS_TYPEDEF_ALL(reg_bus, addr_t, data_t, strb_t)

  reg_bus_req_t s_reg_req;
  reg_bus_rsp_t s_reg_rsp;
  
  // Assign SV interface to structs
  `REG_BUS_ASSIGN_TO_REQ(s_reg_req, regbus_slave)
  `REG_BUS_ASSIGN_FROM_RSP(regbus_slave, s_reg_rsp)

  

  clicint_reg_top #(
    .reg_req_t(reg_bus_req_t),
    .reg_rsp_t(reg_bus_rsp_t),
    .AW(AW)
  ) i_regs (
    .clk_i,
    .rst_ni,
    .reg_req_i(s_reg_req),
    .reg_rsp_o(s_reg_rsp),
    .reg2hw, // Write
    .hw2reg, // Read
    .devmode_i
  );
  
endmodule


