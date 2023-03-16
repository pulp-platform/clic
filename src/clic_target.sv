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
  parameter int unsigned N_SOURCE = 256,
  parameter int unsigned PrioWidth = 8,
  parameter int unsigned ModeWidth = 2,

  // derived parameters do not change this
  localparam int SrcWidth  = $clog2(N_SOURCE)  // derived parameter
) (
  input                        clk_i,
  input                        rst_ni,

  input [N_SOURCE-1:0]         ip_i,
  input [N_SOURCE-1:0]         ie_i,
  input [N_SOURCE-1:0]         le_i,

  input [PrioWidth-1:0]        prio_i [N_SOURCE],
  input [ModeWidth-1:0]        mode_i [N_SOURCE],

  output logic [N_SOURCE-1:0]  claim_o,

  output logic                 irq_valid_o,
  input logic                  irq_ready_i,
  output logic [SrcWidth-1:0]  irq_id_o,
  output logic [PrioWidth-1:0] irq_max_o,
  output logic [ModeWidth-1:0] irq_mode_o
);

  // this only works with 2 or more sources
  `ASSERT_INIT(NumSources_A, N_SOURCE >= 2)

  // align to powers of 2 for simplicity
  // a full binary tree with N levels has 2**N + 2**N-1 nodes
  localparam int NumLevels = $clog2(N_SOURCE);
  logic [2**(NumLevels+1)-2:0]                is_tree;
  logic [2**(NumLevels+1)-2:0][SrcWidth-1:0]  id_tree;
  logic [2**(NumLevels+1)-2:0][PrioWidth-1:0] max_tree;
  logic [2**(NumLevels+1)-2:0][ModeWidth-1:0] mode_tree;

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
          assign max_tree[Pa] = prio_i[offset];
          assign mode_tree[Pa] = mode_i[offset];
        end else begin : gen_tie_off
          assign is_tree[Pa]   = '0;
          assign id_tree[Pa]   = '0;
          assign max_tree[Pa]  = '0;
          assign mode_tree[Pa] = '0;
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
                     (is_tree[C0] & is_tree[C1] & ((logic'(mode_tree[C1] > mode_tree[C0]) | ((logic'(mode_tree[C1] == mode_tree[C0]) & (logic'(max_tree[C1] > max_tree[C0])))))));
        // forwarding muxes
        assign is_tree[Pa]   = (sel               & is_tree[C1])  |
                               ((~sel)            & is_tree[C0]);
        assign id_tree[Pa]   = ({SrcWidth{sel}}   & id_tree[C1])  |
                               ({SrcWidth{~sel}}  & id_tree[C0]);
        assign max_tree[Pa]  = ({PrioWidth{sel}}  & max_tree[C1]) |
                               ({PrioWidth{~sel}} & max_tree[C0]);
        assign mode_tree[Pa] = ({ModeWidth{sel}}  & mode_tree[C1]) |
                               ({ModeWidth{~sel}}  & mode_tree[C0]);
      end
    end : gen_level
  end : gen_tree

  logic irq_valid_d, irq_valid_q;
  logic irq_root_valid;
  logic [SrcWidth-1:0]  irq_root_id, irq_id_d, irq_id_q;
  logic [PrioWidth-1:0] irq_max_d, irq_max_q;
  logic [ModeWidth-1:0] irq_mode_d, irq_mode_q;

  // the results can be found at the tree root
  // TODO: remove useless inequality comparison
  assign irq_root_valid = (max_tree[0] > '0) ? is_tree[0] : 1'b0;
  assign irq_root_id    = (is_tree[0]) ? id_tree[0] : '0;

  // handshake logic to send interrupt to core
  typedef enum logic [1:0] {
    IDLE, ACK, CLAIM
  } irq_state_e;

  irq_state_e irq_state_d, irq_state_q;

  always_comb begin
    irq_id_d = '0; // default: No Interrupt
    irq_max_d = '0;
    irq_mode_d = '0;
    claim_o = '0;

    irq_valid_d = 1'b0;

    irq_state_d = irq_state_q;

    unique case (irq_state_q)
      // we are ready to hand off interrupts
      IDLE:
        if (irq_root_valid) begin
          irq_id_d = irq_root_id;
          irq_max_d = max_tree[0];
          irq_mode_d = mode_tree[0];
          irq_valid_d = 1'b1;
          irq_state_d = ACK;
        end
      // wait for handshake
      ACK: begin
        irq_valid_d = 1'b1;
        irq_id_d    = irq_id_q;
        irq_max_d   = irq_max_q;
        irq_mode_d   = irq_mode_q;
        // level sensitive interrupts (le_i == 1'b0) can be cleared (ip_i goes
        // to 1'b0) and shouldn't fire anymore so we should get unstuck here
        if (!le_i[irq_id_q] && !ip_i[irq_id_q]) begin
          irq_valid_d = 1'b0;
          irq_state_d = IDLE;
        end else if (irq_valid_o && irq_ready_i) begin
          irq_valid_d = 1'b0;
          irq_state_d = CLAIM;
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
      irq_mode_q <= '0;
      irq_state_q <= IDLE;
    end else begin
      irq_valid_q <= irq_valid_d;
      irq_id_q <= irq_id_d;
      irq_max_q <= irq_max_d;
      irq_mode_q <= irq_mode_d;
      irq_state_q <= irq_state_d;
    end
  end

  assign irq_valid_o = irq_valid_q;
  assign irq_id_o    = irq_id_q;

  assign irq_max_o = irq_max_q;
  assign irq_mode_o = irq_mode_q;

endmodule
