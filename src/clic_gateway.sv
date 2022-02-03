// Copyright lowRISC contributors.
// Copyright 2022 ETH Zurich University of Bologna
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

// RISC-V CLIC Gateway

module clic_gateway #(
  parameter int N_SOURCE = 32
) (
  input clk_i,
  input rst_ni,

  input [N_SOURCE-1:0] src_i,
  input [N_SOURCE-1:0] sw_i,      // sw-based edge-triggered interrupts (only when in edge mode)
  input [N_SOURCE-1:0] le_i,      // Level0 Edge1

  input [N_SOURCE-1:0] claim_i, // $onehot0(claim_i)

  output logic [N_SOURCE-1:0] ip_o
);

  logic [N_SOURCE-1:0] set;   // Set: (le_i) ? src_i & ~src_q : src_i ;
  logic [N_SOURCE-1:0] src_q;
  logic [N_SOURCE-1:0] sw_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      src_q <= '0;
      sw_q  <= '0;
    end else begin
      src_q <= src_i;
      sw_q  <= sw_i;
    end
  end

  always_comb begin
    for (int i = 0 ; i < N_SOURCE; i++) begin
      set[i] = (src_i[i] & ~src_q[i]) || (sw_i[i] & ~sw_q[i]);
    end
  end

  // Interrupt pending is set by source (depends on le_i), cleared by claim_i.
  // Until interrupt is claimed, set doesn't affect ip_o.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ip_o <= '0;
    end else begin
      for (int i = 0 ; i < N_SOURCE; i++) begin
        if (le_i[i])
          ip_o[i] <= (ip_o[i] | (set[i] & ~ip_o[i])) & (~(ip_o[i] & claim_i[i]));
        else
          ip_o[i] <= src_i[i]; // ip reflects interrupt lines when level sensitive
      end
    end
  end

endmodule
