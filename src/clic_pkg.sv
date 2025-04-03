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
//
// SPDX-License-Identifier: Apache-2.0

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
