package clic_pkg;

  // Maximum number of VS contexts
  // Currently, we assume this is a multiple of 4
  localparam int unsigned MAX_VSCTXTS = 64;
  localparam int unsigned VSID_W      = $clog2(MAX_VSCTXTS);

  function automatic int unsigned ceildiv(int unsigned dividend, int unsigned divisor);
    return (dividend + divisor - 1) / divisor;
  endfunction

  function automatic int unsigned rounddown(int unsigned value, int unsigned alignment);
    return (value / alignment) * alignment;
  endfunction

endpackage
