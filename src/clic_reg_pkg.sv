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

package clic_reg_pkg;

  parameter int unsigned NumSrc = 256;
  parameter int unsigned ClicIntCtlBits = 8;

  // Address widths within the block
  parameter int BlockAw = 13;

  typedef struct packed {
    struct packed {
      logic        q;
    } nvbits;
    struct packed {
      logic [3:0]  q;
    } nlbits;
    struct packed {
      logic [1:0]  q;
    } nmbits;
  } clic_reg2hw_cliccfg_reg_t;

  typedef struct packed {
    struct packed {
      logic [12:0] q;
    } num_interrupt;
    struct packed {
      logic [7:0]  q;
    } version;
    struct packed {
      logic [3:0]  q;
    } clicintctlbits;
    struct packed {
      logic [5:0]  q;
    } num_trigger;
  } clic_reg2hw_clicinfo_reg_t;

  typedef struct packed {
    logic        q;
  } clic_reg2hw_clicintip_reg_t;

  typedef struct packed {
    logic        q;
  } clic_reg2hw_clicintie_reg_t;

  typedef struct packed {
    struct packed {
      logic        q;
    } shv;
    struct packed {
      logic [1:0]  q;
    } trig;
    struct packed {
      logic [1:0]  q;
    } mode;
  } clic_reg2hw_clicintattr_reg_t;

  typedef struct packed {
    logic [7:0]  q;
  } clic_reg2hw_clicintctrl_reg_t;

  typedef struct packed {
    logic        d;
    logic        de;
  } clic_hw2reg_clicintip_reg_t;

  // Register -> HW type
  typedef struct packed {
    clic_reg2hw_cliccfg_reg_t cliccfg;
    clic_reg2hw_clicinfo_reg_t clicinfo;
    clic_reg2hw_clicintip_reg_t [NumSrc-1:0] clicintip;
    clic_reg2hw_clicintie_reg_t [NumSrc-1:0] clicintie;
    clic_reg2hw_clicintattr_reg_t [NumSrc-1:0] clicintattr;
    clic_reg2hw_clicintctrl_reg_t [NumSrc-1:0] clicintctrl;
  } clic_reg2hw_t;

  // HW -> register type
  typedef struct packed {
    clic_hw2reg_clicintip_reg_t [NumSrc-1:0] clicintip;
  } clic_hw2reg_t;


  // Register offsets
  parameter logic [BlockAw-1:0] CLIC_CLICCFG_OFFSET   = 13'h 0;
  parameter logic [BlockAw-1:0] CLIC_CLICINFO_OFFSET  = 13'h 4;
  parameter logic [BlockAw-1:0] CLIC_CLICINTIP_MASK   = 13'b 1_????_????_00??;
  parameter logic [BlockAw-1:0] CLIC_CLICINTIE_MASK   = 13'b 1_????_????_01??;
  parameter logic [BlockAw-1:0] CLIC_CLICINTATTR_MASK = 13'b 1_????_????_10??;
  parameter logic [BlockAw-1:0] CLIC_CLICINTCTRL_MASK = 13'b 1_????_????_11??;

  // Register width information to check illegal writes
  parameter logic [3:0] CLIC_PERMIT [6] = '{
    4'b 0001, // index[   0] CLIC_CLICCFG
    4'b 1111, // index[   1] CLIC_CLICINFO
    4'b 0001, // index[   2] CLIC_CLICINTIP
    4'b 0001, // index[   3] CLIC_CLICINTIE
    4'b 0001, // index[   4] CLIC_CLICINTATTR
    4'b 0001 // index[   5] CLIC_CLICINTCTRL
  };

endpackage
