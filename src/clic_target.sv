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

//
// RISC-V CLIC Interrupt Generator
//
// This module basically doing IE & IP based on level.
// Keep in mind that increasing MAX_PRIO affects logic size a lot.
//
// The module implements a binary tree to find the maximal entry. the solution
// has O(N) area and O(log(N)) delay complexity, and thus scales well with
// many input sources.
//

`include "common_cells/assertions.svh"

module clic_target #(
  parameter int unsigned N_SOURCE    = 256,
  parameter int unsigned N_PIPE      = 1,
  parameter int unsigned MAX_VSCTXTS = 64,
  parameter int unsigned PrioWidth   = 8,
  parameter int unsigned ModeWidth   = 2,
  parameter int unsigned VsidWidth   = 6,
  parameter int unsigned VsprioWidth = 8,

  // derived parameters do not change this
  localparam int SrcWidth  = $clog2(N_SOURCE)  // derived parameter
) (
  input                        clk_i,
  input                        rst_ni,

  input [N_SOURCE-1:0]         ip_i,
  input [N_SOURCE-1:0]         ie_i,
  input [N_SOURCE-1:0]         le_i,
  input [N_SOURCE-1:0]         shv_i,

  input [PrioWidth-1:0]        prio_i [N_SOURCE],
  input [ModeWidth-1:0]        mode_i [N_SOURCE],
  input logic                  intv_i [N_SOURCE],
  input [VsidWidth-1:0]        vsid_i [N_SOURCE],

  input [VsprioWidth-1:0]      vsprio_i [MAX_VSCTXTS],

  output logic [N_SOURCE-1:0]  claim_o,

  output logic                 irq_valid_o,
  input logic                  irq_ready_i,
  output logic [SrcWidth-1:0]  irq_id_o,
  output logic [PrioWidth-1:0] irq_max_o,
  output logic [ModeWidth-1:0] irq_mode_o,
  output logic [VsidWidth-1:0] irq_vsid_o,
  output logic                 irq_v_o,
  output logic                 irq_shv_o,

  output logic                 irq_kill_req_o,
  input logic                  irq_kill_ack_i,
  input logic                  mnxti_cfg_i
);

  // this only works with 2 or more sources
  `ASSERT_INIT(NumSources_A, N_SOURCE >= 2)

  typedef struct packed {
    logic [ModeWidth-1:0]   mode;
    logic [VsprioWidth-1:0] vsprio;
    logic [PrioWidth-1:0]   prio;
  } prio_t;

  localparam logic [1:0] U_MODE = 2'b00;
  localparam logic [1:0] S_MODE = 2'b01;
  localparam logic [1:0] M_MODE = 2'b11;

  // align to powers of 2 for simplicity
  // a full binary tree with N levels has 2**N + 2**N-1 nodes
  localparam int NumLevels = $clog2(N_SOURCE);
  logic  [2**(NumLevels+1)-2:0]                is_tree, is_tree_q;
  logic  [2**(NumLevels+1)-2:0][SrcWidth-1:0]  id_tree, id_tree_q;
  prio_t [2**(NumLevels+1)-2:0]                max_tree, max_tree_q;

  for (genvar level = 0; level < NumLevels+1; level++) begin : gen_tree
    //
    // level+1   C0   C1   <- "Base1" points to the first node on "level+1",
    //            \  /         these nodes are the children of the nodes one level below
    // level       Pa      <- "Base0", points to the first node on "level",
    //                         these nodes are the parents of the nodes one level above
    //
    // hence we have the following indices for the paPa, C0, C1 nodes:
    // Pa = 2**level     - 1 + offset       = Base0 + offset
    // C0 = 2**(level+1) - 1 + 2*offset     = Base1 + 2*offset
    // C1 = 2**(level+1) - 1 + 2*offset + 1 = Base1 + 2*offset + 1
    //
    localparam int Base0 = (2**level)-1;
    localparam int Base1 = (2**(level+1))-1;

    for (genvar offset = 0; offset < 2**level; offset++) begin : gen_level
      localparam int Pa = Base0 + offset;
      localparam int C0 = Base1 + 2*offset;
      localparam int C1 = Base1 + 2*offset + 1;

      // this assigns the gated interrupt source signals, their
      // corresponding IDs and priorities to the tree leafs
      if (level == NumLevels) begin : gen_leafs
        if (offset < N_SOURCE) begin : gen_assign
          assign is_tree[Pa]  = ip_i[offset] & ie_i[offset];
          assign id_tree[Pa]  = offset;
          // NOTE: save space by encoding the Virtualization bit in the privilege mode tree fields.
          // This is done by temporarily elevating the privilege level of hypervisor IRQs (mode=S_MODE, intv=0)
          // to the reserved value 2'b10 so that they have higher priority than virtualized IRQs (S_MODE == 1'b01)
          // but still lower priority than M_MODE IRQs (M_MODE == 2'b11).
          assign max_tree[Pa].mode   = ((mode_i[offset] == S_MODE) && ~intv_i[offset]) ? 2'b10 : mode_i[offset];
          assign max_tree[Pa].vsprio = ((mode_i[offset] == S_MODE) && intv_i[offset]) ? vsprio_i[vsid_i[offset]] : '0;
          assign max_tree[Pa].prio   = prio_i[offset];
        end else begin : gen_tie_off
          assign is_tree[Pa]   = '0;
          assign id_tree[Pa]   = '0;
          assign max_tree[Pa]  = '0;
        end
      // this creates the node assignments
      end else begin : gen_nodes
        // NOTE: the code below has been written in this way in order to work
        // around a synthesis issue in Vivado 2018.3 and 2019.2 where the whole
        // module would be optimized away if these assign statements contained
        // ternary statements to implement the muxes.
        //
        // TODO: rewrite these lines with ternary statmements onec the problem
        // has been fixed in the tool.
        //
        // See also originating issue:
        // https://github.com/lowRISC/opentitan/issues/1355
        // Xilinx issue:
        // https://forums.xilinx.com/t5/Synthesis/
        // Simulation-Synthesis-Mismatch-with-Vivado-2018-3/m-p/1065923#M33849

        logic sel; // local helper variable
        // in case only one of the parent has a pending irq_o, forward that one
        // in case both irqs are pending, forward the one with higher priority
        assign sel = (~is_tree[C0] & is_tree[C1]) |
                     (is_tree[C0] & is_tree[C1] & logic'(max_tree[C1] > max_tree[C0]));
        // forwarding muxes
        assign is_tree[Pa]   = (sel               & is_tree[C1])  |
                               ((~sel)            & is_tree[C0]);
        assign id_tree[Pa]   = ({SrcWidth{sel}}   & id_tree[C1])  |
                               ({SrcWidth{~sel}}  & id_tree[C0]);
        assign max_tree[Pa].mode    = ({ModeWidth{sel}}   & max_tree[C1].mode)  |
                                      ({ModeWidth{~sel}}  & max_tree[C0].mode);
        assign max_tree[Pa].vsprio  = ({VsprioWidth{sel}}   & max_tree[C1].vsprio)  |
                                      ({VsprioWidth{~sel}}  & max_tree[C0].vsprio);
        assign max_tree[Pa].prio    = ({PrioWidth{sel}}   & max_tree[C1].prio)  |
                                      ({PrioWidth{~sel}}  & max_tree[C0].prio);
      end
    end : gen_level
  end : gen_tree

  logic irq_valid_d, irq_valid_q;
  logic irq_root_valid;
  logic irq_kill_req_d, irq_kill_req_q;
  logic higher_irq;
  logic [SrcWidth-1:0]  irq_root_id, irq_id_d, irq_id_q;
  prio_t                irq_max_d, irq_max_q;
  logic [VsidWidth-1:0] vsid_max_d, vsid_max_q;
  logic                 shv_max_d, shv_max_q;

  if (N_PIPE == 0) begin : gen_no_pipe
    assign max_tree_q = max_tree;
    assign is_tree_q = is_tree;
    assign id_tree_q = id_tree;
  end else begin: gen_pipe
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (~rst_ni) begin
        max_tree_q <= '0;
        is_tree_q <= '0;
        id_tree_q <= '0;
      end else begin
        max_tree_q <= max_tree;
        is_tree_q <= is_tree;
        id_tree_q <= id_tree;
      end
    end
  end

  assign irq_root_valid = (max_tree_q[0] > '0) ? is_tree_q[0] : 1'b0;
  assign irq_root_id    = (is_tree_q[0]) ? id_tree_q[0] : '0;

  // higher level interrupt is available than the one we are currently processing
  // TODO: maybe add pipe?
  assign higher_irq = irq_root_id != irq_id_q;

  // handshake logic to send interrupt to core
  typedef enum logic [1:0] {
    IDLE, ACK, CLAIM
  } irq_state_e;

  irq_state_e irq_state_d, irq_state_q;

  always_comb begin
    irq_id_d = '0; // default: No Interrupt
    irq_max_d = '0;
    vsid_max_d = '0;
    shv_max_d = '0;
    claim_o = '0;

    irq_valid_d = 1'b0;
    irq_kill_req_d = 1'b0;

    irq_state_d = irq_state_q;

    unique case (irq_state_q)
      // we are ready to hand off interrupts
      IDLE:
        if (irq_root_valid) begin
          irq_id_d = irq_root_id;
          irq_max_d = max_tree_q[0];
          vsid_max_d = vsid_i[irq_root_id];
          shv_max_d = shv_i[irq_root_id];
          irq_valid_d = 1'b1;
          irq_state_d = ACK;
        end
      // wait for handshake
      ACK: begin
        irq_valid_d = 1'b1;
        if (!mnxti_cfg_i) begin
          irq_id_d   = irq_id_q;
          irq_max_d  = irq_max_q;
          vsid_max_d = vsid_max_q;
          shv_max_d  = shv_max_q;
        end else begin
          if (irq_root_valid) begin
            irq_id_d = irq_root_id;  // give irq_id_d the most updated value
            irq_max_d = max_tree_q[0]; // give irq_max_d the most updated value
            shv_max_d = shv_i[irq_root_id];
          end else begin
            irq_id_d = '0;
            irq_max_d = '0;
            shv_max_d  = shv_max_q;
          end
        end
        // level sensitive interrupts (le_i == 1'b0) can be cleared (ip_i goes
        // to 1'b0) and shouldn't fire anymore so we should get unstuck here
        if (!le_i[irq_id_q] && !ip_i[irq_id_q]) begin
          irq_valid_d = 1'b0;
          irq_state_d = IDLE;
        end else if (irq_valid_o && irq_ready_i) begin
          irq_valid_d = 1'b0;
          irq_state_d = CLAIM;
        end else if (higher_irq) begin
          // we have a potentially higher level interrupt. Try to kill the
          // current handshake (not irq!) and restart
          irq_kill_req_d = 1'b1;
          if (irq_kill_req_o && irq_kill_ack_i) begin
            irq_kill_req_d = 1'b0;
            irq_valid_d = 1'b0;
            irq_state_d = IDLE;
          end
        end
      end
      // generate interrupt claim pulse
      CLAIM: begin
        claim_o[irq_id_q] = 1'b1;

        irq_state_d = IDLE;
      end
      // shouldn't happen
      default:
        irq_state_d = IDLE;
    endcase // unique case (irq_state_q)
  end


  always_ff @(posedge clk_i or negedge rst_ni) begin : gen_regs
    if (!rst_ni) begin
      irq_valid_q <= 1'b0;
      irq_id_q <= '0;
      irq_max_q <= '0;
      vsid_max_q <= '0;
      shv_max_q <= '0;
      irq_kill_req_q <= 1'b0;
      irq_state_q <= IDLE;
    end else begin
      irq_valid_q <= irq_valid_d;
      irq_id_q <= irq_id_d;
      irq_max_q <= irq_max_d;
      vsid_max_q <= vsid_max_d;
      shv_max_q <= shv_max_d;
      irq_kill_req_q <= irq_kill_req_d;
      irq_state_q <= irq_state_d;
    end
  end

  assign irq_valid_o = irq_valid_q;
  assign irq_id_o    = irq_id_q;

  assign irq_max_o = irq_max_q.prio;
  // NOTE: If the interrupt priority was modified (see note above), restore nominal privilege
  assign irq_mode_o = (irq_max_q.mode == 2'b10) ? S_MODE : irq_max_q.mode;
  assign irq_vsid_o = vsid_max_q;
  assign irq_v_o    = logic'(irq_max_q.mode == S_MODE);
  assign irq_shv_o  = shv_max_q;

  assign irq_kill_req_o = irq_kill_req_q;

endmodule
