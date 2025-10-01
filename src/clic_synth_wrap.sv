// Copyright 2025 ETH Zurich and University of Bologna.
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

module clic_synth_wrap
  import clic_synth_pkg::*;
(
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  reg_req_t                 reg_req_i,
  output reg_rsp_t                 reg_rsp_o,
  input  logic      [N_SOURCE-1:0] intr_src_i,
  output logic                     irq_valid_o,
  input  logic                     irq_ready_i,
  output logic         [SRC_W-1:0] irq_id_o,
  output logic               [7:0] irq_level_o,
  output logic                     irq_shv_o,
  output logic               [1:0] irq_priv_o,
  output logic                     irq_kill_req_o,
  input  logic                     irq_kill_ack_i
);

  clic #(
    .reg_req_t  ( reg_req_t  ),
    .reg_rsp_t  ( reg_rsp_t  ),
    .N_SOURCE   ( N_SOURCE   ),
    .INTCTLBITS ( INTCTLBITS ),
    .SSCLIC     ( SSCLIC     ),
    .USCLIC     ( USCLIC     )
  ) i_clic (
    .clk_i          ( clk_i          ),
    .rst_ni         ( rst_ni         ),
    .reg_req_i      ( reg_req_i      ),
    .reg_rsp_o      ( reg_rsp_o      ),
    .intr_src_i     ( intr_src_i     ),
    .irq_valid_o    ( irq_valid_o    ),
    .irq_ready_i    ( irq_ready_i    ),
    .irq_id_o       ( irq_id_o       ),
    .irq_level_o    ( irq_level_o    ),
    .irq_shv_o      ( irq_shv_o      ),
    .irq_priv_o     ( irq_priv_o     ),
    .irq_kill_req_o ( irq_kill_req_o ),
    .irq_kill_ack_i ( irq_kill_ack_i )
  );

endmodule
