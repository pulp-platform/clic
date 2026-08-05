// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSES/SHL-0.51.txt for details.
// SPDX-License-Identifier: SHL-0.51

package clic_pkg;

  // Maximum number of VS contexts
  // Currently, we assume this is a multiple of 4
  localparam int unsigned MAX_VSCTXTS = 64;
  localparam int unsigned VSID_W      = $clog2(MAX_VSCTXTS);

  function automatic int unsigned rounddown(int unsigned value, int unsigned alignment);
    return (value / alignment) * alignment;
  endfunction

endpackage
