// Copyright 2026 ETH Zurich and University of Bologna.
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
//
// Self-checking testbench for the CLIC.
//
// The DUT is clic_apb. Stimulus is black-box: interrupt sources are driven on
// `intr_src_i` and all configuration goes over APB. Observation is white-box
// where the boundary does not expose enough (`claim`, `ip`), because the claim
// pulse is what closes the claim -> ip -> selection-tree loop.

module tb_clic #(
  parameter int unsigned N_SOURCE     = 16,
  parameter int unsigned INTCTLBITS   = 8,
  parameter bit          SSCLIC       = 1,
  parameter bit          USCLIC       = 0,
  parameter bit          VSCLIC       = 1,
  parameter int unsigned N_VSCTXTS    = 4,
  parameter bit          VSPRIO       = 1,
  parameter int unsigned VSPRIO_W     = 1,
  // Cycles to wait after freezing stimulus before the selection result is
  // required to match the reference model. Grows with clic_target pipelining.
  parameter int unsigned SettleCycles  = 8,
  parameter int unsigned TimeoutCycles = 2_000_000,
  parameter time         ClkPeriod     = 10ns
);

  import clic_pkg::*;

  localparam int unsigned SrcW  = $clog2(N_SOURCE);
  localparam int unsigned KeyW  = 2 + VSPRIO_W + INTCTLBITS;

  // Two distinct source indices valid for any legal N_SOURCE, so the directed
  // tests run unchanged from N_SOURCE=2 up.
  localparam int unsigned IdxLo = 0;
  localparam int unsigned IdxHi = N_SOURCE - 1;

  localparam logic [1:0] U_MODE = 2'b00;
  localparam logic [1:0] S_MODE = 2'b01;
  localparam logic [1:0] M_MODE = 2'b11;

  // Register map, mirrored from clic.sv
  localparam logic [31:0] MCLICCFG_ADDR   = 32'h0_0000;
  localparam logic [31:0] MCLICINT_BASE   = 32'h0_1000;
  localparam logic [31:0] SCLICINTV_BASE  = 32'h0_d000;
  localparam logic [31:0] VSCLICPRIO_BASE = 32'h0_e000;

  //////////////////
  // Clock, reset //
  //////////////////

  logic clk, rst_n;

  clk_rst_gen #(
    .ClkPeriod    (ClkPeriod),
    .RstClkCycles (5)
  ) i_clk_rst_gen (
    .clk_o  (clk),
    .rst_no (rst_n)
  );

  sim_timeout #(.Cycles(TimeoutCycles)) i_sim_timeout (.clk_i(clk), .rst_ni(rst_n));

  ///////////////////
  // DUT and ports //
  ///////////////////

  // APB request/response
  logic        psel, penable, pwrite, pready, pslverr;
  logic [31:0] paddr, pwdata, prdata;

  logic [N_SOURCE-1:0] intr_src;

  logic              irq_valid, irq_ready;
  logic [SrcW-1:0]   irq_id;
  logic [7:0]        irq_level;
  logic              irq_shv, irq_v;
  logic [1:0]        irq_priv;
  logic [VSID_W-1:0] irq_vsid;
  logic              irq_kill_req, irq_kill_ack;

  // The DUT is the APB-wrapped CLIC, so the bus adapter is inside the verified
  // scope rather than bypassed.
  clic_apb #(
    .N_SOURCE   (N_SOURCE),
    .INTCTLBITS (INTCTLBITS),
    .SSCLIC     (SSCLIC),
    .USCLIC     (USCLIC),
    .VSCLIC     (VSCLIC),
    .N_VSCTXTS  (N_VSCTXTS),
    .VSPRIO     (VSPRIO),
    .VSPRIO_W   (VSPRIO_W)
  ) dut (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .penable_i      (penable),
    .pwrite_i       (pwrite),
    .paddr_i        (paddr),
    .psel_i         (psel),
    .pwdata_i       (pwdata),
    .prdata_o       (prdata),
    .pready_o       (pready),
    .pslverr_o      (pslverr),
    .intr_src_i     (intr_src),
    .irq_valid_o    (irq_valid),
    .irq_ready_i    (irq_ready),
    .irq_id_o       (irq_id),
    .irq_level_o    (irq_level),
    .irq_shv_o      (irq_shv),
    .irq_priv_o     (irq_priv),
    .irq_vsid_o     (irq_vsid),
    .irq_v_o        (irq_v),
    .irq_kill_req_o (irq_kill_req),
    .irq_kill_ack_i (irq_kill_ack)
  );

  // Internals reached hierarchically: `ip` and `claim` are not on the boundary,
  // and the claim -> ip loop is exactly what the selection checks depend on.
  `define CLIC_IP    dut.i_clic.ip
  `define CLIC_CLAIM dut.i_clic.claim

  ///////////////////////////
  // Error bookkeeping     //
  ///////////////////////////

  // Cap on reported failures: the always-on monitors fire every cycle, so a
  // single broken behaviour can otherwise bury the log. Counting continues.
  localparam int unsigned MaxReportedErrors = 50;

  int unsigned n_errors;
  int unsigned n_checks;
  string       current_test;

  // Deliberately $display rather than $error: Verilator treats $error as an
  // immediate $stop, which would abort on the first failure and never print the
  // summary, while Questa carries on. Reporting through $display and deciding
  // pass/fail once at the end makes both simulators behave identically and lets
  // a single run show every failure.
  task automatic chk(input bit cond, input string msg);
    n_checks++;
    if (!cond) begin
      n_errors++;
      if (n_errors <= MaxReportedErrors) begin
        $display("ERROR [%0t] [%s] %s", $time, current_test, msg);
      end else if (n_errors == MaxReportedErrors + 1) begin
        $display("ERROR ... further failures suppressed");
      end
    end
  endtask

  ///////////////////////////////
  // Shadow configuration model //
  ///////////////////////////////

  logic [7:0]          cfg_ctl    [N_SOURCE];
  logic [1:0]          cfg_mode   [N_SOURCE];
  logic                cfg_shv    [N_SOURCE];
  logic                cfg_le     [N_SOURCE]; // 1 = edge, 0 = level
  logic                cfg_ie     [N_SOURCE];
  logic [VSID_W-1:0]   cfg_vsid   [N_SOURCE];
  logic                cfg_intv   [N_SOURCE];
  logic [VSPRIO_W-1:0] cfg_vsprio [MAX_VSCTXTS];
  logic [3:0]          cfg_mnlbits;
  logic [1:0]          cfg_nmbits;

  ////////////////////////////
  // Register access tasks  //
  ////////////////////////////
  //
  // Everything below this line goes through cfg_write/cfg_read only, so the bus
  // front-end can be swapped by rewriting just these two tasks.

  // Standard two-phase APB transfer: setup phase (psel, no penable) followed by
  // the access phase (psel and penable) held until pready.
  task automatic cfg_write(input logic [31:0] addr, input logic [31:0] data);
    @(posedge clk);
    psel <= 1'b1; penable <= 1'b0; pwrite <= 1'b1; paddr <= addr; pwdata <= data;
    @(posedge clk);
    penable <= 1'b1;
    forever begin
      @(posedge clk);
      if (pready === 1'b1) break;
    end
    chk(pslverr !== 1'b1, $sformatf("pslverr on write to 0x%08x", addr));
    psel <= 1'b0; penable <= 1'b0; pwrite <= 1'b0;
  endtask

  task automatic cfg_read(input logic [31:0] addr, output logic [31:0] data);
    @(posedge clk);
    psel <= 1'b1; penable <= 1'b0; pwrite <= 1'b0; paddr <= addr;
    @(posedge clk);
    penable <= 1'b1;
    forever begin
      @(posedge clk);
      if (pready === 1'b1) break;
    end
    data = prdata;
    chk(pslverr !== 1'b1, $sformatf("pslverr on read from 0x%08x", addr));
    psel <= 1'b0; penable <= 1'b0;
  endtask

  // Write one clicint register and update the shadow.
  task automatic set_int(input int unsigned i,
                         input logic [7:0]  ctl,
                         input logic [1:0]  mode,
                         input logic        edge_trig,
                         input logic        shv,
                         input logic        ie);
    logic [31:0] w;
    w = '0;
    w[31:24] = ctl;
    w[23:22] = mode;
    w[18:17] = {1'b0, edge_trig};
    w[16]    = shv;
    w[8]     = ie;
    cfg_ctl[i]  = ctl;
    cfg_mode[i] = mode;
    cfg_le[i]   = edge_trig;
    cfg_shv[i]  = shv;
    cfg_ie[i]   = ie;
    cfg_write(MCLICINT_BASE + 4*i, w);
  endtask

  // Write one clicintv field group. The register holds four sources; the other
  // three are rewritten from the shadow so this is a read-modify-write in the
  // model rather than on the bus.
  //
  // NOTE: clic.sv zeroes the write data of any lane whose source is configured
  // above S-mode, so an M-mode source cannot be given a VS id. The shadow has
  // to replicate that or it diverges from the register file.
  task automatic set_intv(input int unsigned i,
                          input logic        v,
                          input logic [VSID_W-1:0] vsid);
    logic [31:0] w;
    int unsigned base;
    cfg_intv[i] = v;
    cfg_vsid[i] = vsid;
    base = (i / 4) * 4;
    for (int unsigned k = 0; k < 4; k++) begin
      if ((base + k < N_SOURCE) && (cfg_mode[base+k] > S_MODE)) begin
        cfg_intv[base+k] = 1'b0;
        cfg_vsid[base+k] = '0;
      end
    end
    w = '0;
    for (int unsigned k = 0; k < 4; k++) begin
      if (base + k < N_SOURCE) begin
        w[8*k]         = cfg_intv[base+k];
        w[8*k+7 -: 6]  = cfg_vsid[base+k];
      end
    end
    cfg_write(SCLICINTV_BASE + 4*(i/4), w);
  endtask

  task automatic set_vsprio(input int unsigned vs, input logic [VSPRIO_W-1:0] prio);
    logic [31:0] w;
    int unsigned base;
    cfg_vsprio[vs] = prio;
    base = (vs / 4) * 4;
    w = '0;
    for (int unsigned k = 0; k < 4; k++) begin
      w[8*k +: VSPRIO_W] = cfg_vsprio[base+k];
    end
    cfg_write(VSCLICPRIO_BASE + 4*(vs/4), w);
  endtask

  task automatic set_mcliccfg(input logic [3:0] mnlbits, input logic [1:0] nmbits);
    logic [31:0] w;
    cfg_mnlbits = mnlbits;
    cfg_nmbits  = nmbits;
    w = '0;
    w[3:0] = mnlbits;
    w[5:4] = nmbits;
    cfg_write(MCLICCFG_ADDR, w);
  endtask

  // Disable every source and clear all attributes.
  task automatic reset_config();
    set_mcliccfg(4'd8, 2'd2);
    for (int unsigned i = 0; i < N_SOURCE; i++) begin
      set_int(i, 8'h00, M_MODE, 1'b0, 1'b0, 1'b0);
    end
    if (VSCLIC) begin
      for (int unsigned i = 0; i < N_SOURCE; i++) begin
        cfg_intv[i] = 1'b0;
        cfg_vsid[i] = '0;
      end
      for (int unsigned i = 0; i < N_SOURCE; i += 4) begin
        cfg_write(SCLICINTV_BASE + 4*(i/4), 32'h0);
      end
    end
    if (VSCLIC && VSPRIO) begin
      for (int unsigned vs = 0; vs < MAX_VSCTXTS; vs++) cfg_vsprio[vs] = '0;
      for (int unsigned vs = 0; vs < MAX_VSCTXTS; vs += 4) begin
        cfg_write(VSCLICPRIO_BASE + 4*(vs/4), 32'h0);
      end
    end
  endtask

  /////////////////////
  // Reference model //
  /////////////////////

  // Selection key, mirroring the leaf encoding in clic_target: hypervisor
  // (non-virtual S-mode) interrupts are lifted to 2'b10 so they outrank
  // virtualised ones but stay below M-mode.
  function automatic logic [KeyW-1:0] ref_key(input int unsigned i);
    logic [1:0]          m_eff;
    logic [VSPRIO_W-1:0] vp_eff;
    m_eff  = ((cfg_mode[i] == S_MODE) && !cfg_intv[i]) ? 2'b10 : cfg_mode[i];
    vp_eff = ((cfg_mode[i] == S_MODE) &&  cfg_intv[i]) ? cfg_vsprio[cfg_vsid[i]]
                                                       : {VSPRIO_W{1'b0}};
    return {m_eff, vp_eff, cfg_ctl[i][INTCTLBITS-1:0]};
  endfunction

  // Highest-priority pending and enabled source. Ties resolve to the lowest
  // index, because the tree's select condition is a strict greater-than and
  // the low-index subtree sits on the C0 input.
  //
  // Uses the DUT's `ip` rather than modelling the gateway, so this checks the
  // selection logic in isolation. Gateway behaviour is covered separately by
  // the directed edge/level tests.
  function automatic void ref_argmax(output bit valid, output int unsigned id);
    logic [KeyW-1:0] best, k;
    valid = 1'b0;
    id    = 0;
    best  = '0;
    for (int unsigned i = 0; i < N_SOURCE; i++) begin
      if (`CLIC_IP[i] === 1'b1 && cfg_ie[i] === 1'b1) begin
        k = ref_key(i);
        if (!valid || (k > best)) begin
          valid = 1'b1;
          best  = k;
          id    = i;
        end
      end
    end
    // clic_target suppresses an all-zero key (U-mode with zero control value).
    if (valid && (best == {KeyW{1'b0}})) valid = 1'b0;
  endfunction

  // irq_level_o after the mnlbits masking in clic.sv.
  function automatic logic [7:0] ref_level(input int unsigned i);
    logic [7:0]  r;
    int unsigned nl;
    nl = (cfg_mnlbits <= INTCTLBITS) ? cfg_mnlbits : INTCTLBITS;
    r  = 8'hff;
    for (int unsigned k = 0; k < nl; k++) r[7-k] = cfg_ctl[i][7-k];
    return r;
  endfunction

  // clic_target restores the nominal privilege before driving irq_mode_o.
  function automatic logic [1:0] ref_mode(input int unsigned i);
    logic [1:0] m_eff;
    m_eff = ((cfg_mode[i] == S_MODE) && !cfg_intv[i]) ? 2'b10 : cfg_mode[i];
    return (m_eff == 2'b10) ? S_MODE : m_eff;
  endfunction

  // irq_priv_o after the nmbits masking in clic.sv.
  function automatic logic [1:0] ref_priv(input int unsigned i);
    logic [1:0] nm, m;
    nm = '0;
    if (VSCLIC || SSCLIC || USCLIC)        nm[0] = cfg_nmbits[0];
    if ((VSCLIC || SSCLIC) && USCLIC)      nm[1] = cfg_nmbits[1];
    m = ref_mode(i);
    case (nm)
      2'd0:    return M_MODE;
      2'd1:    return {m[1], 1'b1};
      default: return m;
    endcase
  endfunction

  function automatic logic ref_v(input int unsigned i);
    return ((cfg_mode[i] == S_MODE) && cfg_intv[i]);
  endfunction

  ///////////////////////////////////////////////
  // Always-on invariants (latency-independent) //
  ///////////////////////////////////////////////

  logic                prev_valid, prev_ready, prev_hs;
  logic [SrcW-1:0]     prev_id, prev_hs_id;
  logic [7:0]          prev_level;
  logic [1:0]          prev_priv;
  logic [N_SOURCE-1:0] prev_ip;

  always @(posedge clk) begin
    if (!rst_n) begin
      prev_valid <= 1'b0;
      prev_ready <= 1'b0;
      prev_hs    <= 1'b0;
      prev_id    <= '0;
      prev_hs_id <= '0;
      prev_level <= '0;
      prev_priv  <= '0;
      prev_ip    <= '0;
    end else begin
      // I1: at most one source may be claimed at a time; the gateway relies on it
      chk($onehot0(`CLIC_CLAIM), $sformatf("claim not onehot0: %b", `CLIC_CLAIM));

      // I2: the payload presented alongside irq_valid_o must describe irq_id_o
      if (irq_valid) begin
        chk(irq_level === ref_level(irq_id),
            $sformatf("irq_level_o=%02x, expected %02x for id %0d",
                      irq_level, ref_level(irq_id), irq_id));
        chk(irq_priv === ref_priv(irq_id),
            $sformatf("irq_priv_o=%0d, expected %0d for id %0d",
                      irq_priv, ref_priv(irq_id), irq_id));
        chk(irq_shv === cfg_shv[irq_id],
            $sformatf("irq_shv_o=%0b, expected %0b for id %0d",
                      irq_shv, cfg_shv[irq_id], irq_id));
        chk(irq_v === ref_v(irq_id),
            $sformatf("irq_v_o=%0b, expected %0b for id %0d",
                      irq_v, ref_v(irq_id), irq_id));
        chk(irq_vsid === cfg_vsid[irq_id],
            $sformatf("irq_vsid_o=%0d, expected %0d for id %0d",
                      irq_vsid, cfg_vsid[irq_id], irq_id));
      end

      // I3: the offer must not change underneath a stalled consumer
      if (prev_valid && !prev_ready && irq_valid) begin
        chk(irq_id === prev_id,
            $sformatf("irq_id_o changed %0d -> %0d while stalled", prev_id, irq_id));
        chk(irq_level === prev_level, "irq_level_o changed while stalled");
        chk(irq_priv === prev_priv, "irq_priv_o changed while stalled");
      end

      // I4: a claim may only follow a completed handshake for the same id
      if (|`CLIC_CLAIM) begin
        chk(prev_hs, "claim asserted without a preceding valid/ready handshake");
        if (prev_hs) begin
          chk(`CLIC_CLAIM[prev_hs_id] === 1'b1,
              $sformatf("claim id mismatch: claim=%b, handshake id=%0d",
                        `CLIC_CLAIM, prev_hs_id));
        end
      end

      // I5: never claim a disabled source
      for (int unsigned i = 0; i < N_SOURCE; i++) begin
        if (`CLIC_CLAIM[i]) begin
          chk(cfg_ie[i] === 1'b1, $sformatf("claim of disabled source %0d", i));
        end
      end

      // I6: a new offer must correspond to a source that really was pending and
      // enabled when the selection decision was taken, i.e. in the previous
      // cycle. Sampling `ip` in the current cycle would false-positive on a
      // level source that de-asserts exactly as the offer goes out.
      //
      // This is the invariant that catches a stale selection result: a
      // pipelined tree that still shows a just-claimed source will raise an
      // offer here with prev_ip already cleared. The spurious offer is
      // transient (the FSM kills it a few cycles later via higher_irq), so it
      // MUST be caught continuously -- a settle-then-sample check misses it.
      if (irq_valid && !prev_valid) begin
        chk(prev_ip[irq_id] === 1'b1,
            $sformatf("offer raised for source %0d which was not pending", irq_id));
        chk(cfg_ie[irq_id] === 1'b1,
            $sformatf("offer raised for disabled source %0d", irq_id));
      end

      prev_ip    <= `CLIC_IP;
      prev_valid <= irq_valid;
      prev_ready <= irq_ready;
      prev_id    <= irq_id;
      prev_level <= irq_level;
      prev_priv  <= irq_priv;
      prev_hs    <= irq_valid && irq_ready;
      prev_hs_id <= irq_id;
    end
  end

  ///////////////////////
  // Consumer / driver //
  ///////////////////////

  int unsigned kill_ack_delay;
  bit          kill_ack_en;

  // Acknowledge kill requests after a configurable delay.
  initial begin
    irq_kill_ack = 1'b0;
    forever begin
      @(posedge clk);
      if (rst_n && kill_ack_en && irq_kill_req) begin
        repeat (kill_ack_delay) @(posedge clk);
        irq_kill_ack <= 1'b1;
        @(posedge clk);
        irq_kill_ack <= 1'b0;
      end
    end
  end

  // Wait for an interrupt offer, then complete the handshake. Returns the id.
  task automatic accept_irq(output int unsigned id, input int unsigned timeout = 500);
    int unsigned waited;
    waited = 0;
    while (!irq_valid) begin
      @(posedge clk);
      waited++;
      if (waited > timeout) begin
        chk(1'b0, "timed out waiting for irq_valid_o");
        id = 0;
        return;
      end
    end
    id = irq_id;
    irq_ready <= 1'b1;
    @(posedge clk);
    irq_ready <= 1'b0;
  endtask

  // Wait for irq_valid_o, failing the test rather than hanging on timeout.
  task automatic await_irq(input string what, input int unsigned timeout = 500);
    int unsigned waited;
    waited = 0;
    while (!irq_valid) begin
      @(posedge clk);
      waited++;
      if (waited > timeout) begin
        chk(1'b0, $sformatf("timed out waiting for %s", what));
        return;
      end
    end
  endtask

  // Wait until no interrupt is offered for `SettleCycles` consecutive cycles.
  task automatic quiesce();
    int unsigned stable;
    stable = 0;
    while (stable < SettleCycles) begin
      @(posedge clk);
      stable++;
    end
  endtask

  ///////////////////
  // Directed tests //
  ///////////////////

  // An edge-triggered source must fire exactly once per rising edge on the
  // source line. This is the check that a pipelined selection tree can break:
  // if the tree still shows the claimed source after the claim, it re-fires.
  task automatic test_edge_fires_once();
    int unsigned id;
    current_test = "edge_fires_once";
    reset_config();
    set_int(IdxHi, 8'hff, M_MODE, 1'b1 /*edge*/, 1'b0, 1'b1);

    intr_src[IdxHi] <= 1'b1;
    @(posedge clk);
    intr_src[IdxHi] <= 1'b0;

    accept_irq(id);
    chk(id == IdxHi, $sformatf("expected id %0d, got %0d", IdxHi, id));

    // No new rising edge, so nothing more may be presented.
    quiesce();
    chk(!irq_valid, "edge interrupt re-fired after being claimed");
    chk(`CLIC_IP[IdxHi] === 1'b0, "ip not cleared by claim");
  endtask

  // A level-triggered source that de-asserts while the offer is outstanding
  // must withdraw the offer and must not be claimed.
  task automatic test_level_deassert_during_ack();
    current_test = "level_deassert_during_ack";
    reset_config();
    set_int(IdxHi, 8'hff, M_MODE, 1'b0 /*level*/, 1'b0, 1'b1);

    irq_ready <= 1'b0;
    intr_src[IdxHi] <= 1'b1;

    // Wait for the offer, but never accept it.
    await_irq("level source offer");
    chk(irq_id == IdxHi, $sformatf("expected id %0d, got %0d", IdxHi, irq_id));

    intr_src[IdxHi] <= 1'b0;
    quiesce();
    chk(!irq_valid, "offer not withdrawn after level source de-asserted");
    chk(!(|`CLIC_CLAIM), "claimed a source that de-asserted before handshake");
  endtask

  // A higher-priority source arriving while an offer is outstanding must cause
  // the CLIC to request a kill and then re-present the higher-priority source.
  task automatic test_preempt_kill();
    int unsigned id, waited;
    current_test = "preempt_kill";
    reset_config();
    set_int(IdxLo, 8'h10, M_MODE, 1'b0, 1'b0, 1'b1); // low priority
    set_int(IdxHi, 8'hf0, M_MODE, 1'b0, 1'b0, 1'b1); // high priority

    irq_ready <= 1'b0;
    intr_src[IdxLo] <= 1'b1;

    await_irq("low-priority offer");
    chk(irq_id == IdxLo, $sformatf("expected id %0d first, got %0d", IdxLo, irq_id));

    // Higher priority arrives while the consumer is stalled.
    intr_src[IdxHi] <= 1'b1;

    waited = 0;
    while (!irq_kill_req) begin
      @(posedge clk);
      waited++;
      if (waited > 200) begin
        chk(1'b0, "no kill request after higher-priority source arrived");
        return;
      end
    end

    // kill_ack_en drives the acknowledge; wait for the request to drop.
    waited = 0;
    while (irq_kill_req) begin
      @(posedge clk);
      waited++;
      if (waited > 200) begin
        chk(1'b0, "kill request not withdrawn after acknowledge");
        return;
      end
    end

    accept_irq(id);
    chk(id == IdxHi,
        $sformatf("expected higher-priority id %0d after kill, got %0d", IdxHi, id));

    intr_src <= '0;
  endtask

  // Two sources with an identical selection key must resolve to the lower
  // index.
  task automatic test_priority_tie();
    current_test = "priority_tie";
    reset_config();
    set_int(IdxLo, 8'h80, M_MODE, 1'b0, 1'b0, 1'b1);
    set_int(IdxHi, 8'h80, M_MODE, 1'b0, 1'b0, 1'b1); // identical key

    irq_ready <= 1'b0;
    intr_src[IdxLo] <= 1'b1;
    intr_src[IdxHi] <= 1'b1;
    quiesce();

    chk(irq_valid, "no offer with two tied sources pending");
    if (irq_valid) begin
      chk(irq_id == IdxLo,
          $sformatf("tie must resolve to lower index %0d, got %0d", IdxLo, irq_id));
    end

    intr_src <= '0;
    quiesce();
  endtask

  // clic_target suppresses a selection whose whole key is zero (U-mode source
  // with a zero control value). A source with the same mode but a non-zero
  // control value must still be offered, so this pins the guard rather than
  // just "nothing fires".
  task automatic test_zero_key_suppressed();
    current_test = "zero_key_suppressed";
    reset_config();

    // U-mode, zero control value -> key is all zeroes -> must not be offered.
    set_int(IdxLo, 8'h00, U_MODE, 1'b0, 1'b0, 1'b1);
    irq_ready <= 1'b0;
    intr_src[IdxLo] <= 1'b1;
    quiesce();
    chk(!irq_valid, "zero-key (U-mode, ctl=0) source must not be offered");
    chk(`CLIC_IP[IdxLo] === 1'b1, "source should still be pending");

    // Same source, non-zero control value -> must be offered.
    set_int(IdxLo, 8'h01, U_MODE, 1'b0, 1'b0, 1'b1);
    quiesce();
    chk(irq_valid, "U-mode source with non-zero ctl must be offered");
    if (irq_valid) chk(irq_id == IdxLo, $sformatf("expected id %0d", IdxLo));

    intr_src <= '0;
    quiesce();
  endtask

  // Among virtualised S-mode interrupts, the VS priority outranks the per-source
  // control value. The source with the higher VS priority is deliberately placed
  // at the HIGHER index: if vsprio were ignored the keys would tie and the
  // low-index tie-break would win, so this fails loudly rather than silently.
  task automatic test_vsprio_ordering();
    if (!(VSCLIC && VSPRIO && SSCLIC)) return;

    current_test = "vsprio_ordering";
    reset_config();

    // Identical mode and control value, so only vsprio can separate them.
    set_int(IdxLo, 8'h40, S_MODE, 1'b0, 1'b0, 1'b1);
    set_int(IdxHi, 8'h40, S_MODE, 1'b0, 1'b0, 1'b1);
    set_intv(IdxLo, 1'b1, 6'd1);
    set_intv(IdxHi, 1'b1, 6'd2);
    set_vsprio(1, 1'b0);
    set_vsprio(2, 1'b1); // VS2 outranks VS1

    irq_ready <= 1'b0;
    intr_src[IdxLo] <= 1'b1;
    intr_src[IdxHi] <= 1'b1;
    quiesce();

    chk(irq_valid, "no offer with two virtualised sources pending");
    if (irq_valid) begin
      chk(irq_id == IdxHi,
          $sformatf("higher vsprio (id %0d) must win over lower index %0d, got %0d",
                    IdxHi, IdxLo, irq_id));
      chk(irq_v === 1'b1, "virtualised source must report irq_v_o");
      chk(irq_vsid == 6'd2, $sformatf("expected vsid 2, got %0d", irq_vsid));
    end

    // Swap the VS priorities: the winner must follow, not the index.
    set_vsprio(1, 1'b1);
    set_vsprio(2, 1'b0);
    quiesce();
    chk(irq_valid, "no offer after swapping VS priorities");
    if (irq_valid) begin
      chk(irq_id == IdxLo,
          $sformatf("after swap, id %0d should win, got %0d", IdxLo, irq_id));
    end

    intr_src <= '0;
    quiesce();
  endtask

  // Every decoded window is larger than the number of registers behind it, so
  // there are addresses that decode but are not implemented. Those must still
  // terminate the bus transfer. An unguarded index would drive `ready` from an
  // out-of-bounds array read and hang the master forever.
  //
  // cfg_read has no timeout of its own, so the bounded wait is done here.
  task automatic apb_read_bounded(input logic [31:0] addr,
                                  input string       label,
                                  output logic [31:0] data);
    int unsigned waited;
    @(posedge clk);
    psel <= 1'b1; penable <= 1'b0; pwrite <= 1'b0; paddr <= addr;
    @(posedge clk);
    penable <= 1'b1;
    waited = 0;
    data   = '0;
    forever begin
      @(posedge clk);
      waited++;
      if (pready === 1'b1) break;
      if (waited > 32) begin
        chk(1'b0, $sformatf("bus hang: %s (0x%05x) never asserted pready (pready=%b)",
                            label, addr, pready));
        psel <= 1'b0; penable <= 1'b0;
        return;
      end
    end
    data = prdata;
    chk(data !== 32'hxxxx_xxxx, $sformatf("%s (0x%05x) returned x on prdata", label, addr));
    psel <= 1'b0; penable <= 1'b0;
  endtask

  task automatic test_unmapped_addresses();
    logic [31:0] rd;
    current_test = "unmapped_addresses";
    reset_config();

    // clicint: implemented up to N_SOURCE, window runs to 0x4fff.
    apb_read_bounded(MCLICINT_BASE,                    "clicint first",     rd);
    apb_read_bounded(MCLICINT_BASE + 4*(N_SOURCE-1),   "clicint last",      rd);
    apb_read_bounded(MCLICINT_BASE + 4*N_SOURCE,       "clicint unmapped",  rd);
    apb_read_bounded(32'h0_4ffc,                       "clicint window top", rd);

    if (VSCLIC) begin
      // clicintv: one register per four sources, window runs to 0xdfff.
      apb_read_bounded(SCLICINTV_BASE,                        "clicintv first",    rd);
      apb_read_bounded(SCLICINTV_BASE + 4*(((N_SOURCE+3)/4)), "clicintv unmapped", rd);
      apb_read_bounded(32'h0_dffc,                            "clicintv win top",  rd);
    end

    if (VSCLIC && VSPRIO) begin
      // clicvs: MAX_VSCTXTS/4 registers, window runs to 0xefff.
      apb_read_bounded(VSCLICPRIO_BASE,                       "clicvs first",      rd);
      apb_read_bounded(VSCLICPRIO_BASE + 4*(MAX_VSCTXTS/4),   "clicvs unmapped",   rd);
      apb_read_bounded(32'h0_effc,                            "clicvs win top",    rd);
    end

    // Fully undecoded address: already handled by the top level case default.
    apb_read_bounded(32'h0_7000, "undecoded", rd);
  endtask

  // With stimulus frozen, the presented interrupt must be the reference argmax.
  // Latency-tolerant by construction: it only compares after settling.
  task automatic test_priority_quiesced(input int unsigned n_rounds);
    bit          exp_valid;
    int unsigned exp_id;
    current_test = "priority_quiesced";

    for (int unsigned round = 0; round < n_rounds; round++) begin
      reset_config();

      // Random static configuration, level-triggered so `ip` tracks the source.
      // Odd rounds draw control values from a narrow range so that exact key
      // ties occur and the tie-break is actually exercised; U-mode is included
      // so that zero-key suppression is hit too.
      for (int unsigned i = 0; i < N_SOURCE; i++) begin
        logic [7:0] ctl;
        logic [1:0] mode;
        ctl = (round % 2 == 1) ? $urandom_range(0, 3) : $urandom_range(0, 255);
        case ($urandom_range(0, 3))
          0:       mode = U_MODE;
          1:       mode = SSCLIC ? S_MODE : M_MODE;
          default: mode = M_MODE;
        endcase
        set_int(i, ctl, mode, 1'b0 /*level*/, $urandom_range(0, 1), $urandom_range(0, 1));
      end
      if (VSCLIC) begin
        for (int unsigned i = 0; i < N_SOURCE; i++) begin
          set_intv(i, $urandom_range(0, 1), $urandom_range(1, N_VSCTXTS));
        end
        if (VSPRIO) begin
          for (int unsigned vs = 0; vs <= N_VSCTXTS; vs++) begin
            set_vsprio(vs, $urandom_range(0, (1 << VSPRIO_W) - 1));
          end
        end
      end

      // Freeze a random pending set and let the selection settle.
      irq_ready <= 1'b0;
      for (int unsigned i = 0; i < N_SOURCE; i++) intr_src[i] <= $urandom_range(0, 1);
      quiesce();

      ref_argmax(exp_valid, exp_id);
      chk(irq_valid === exp_valid,
          $sformatf("round %0d: irq_valid_o=%0b, expected %0b (ip=%b)",
                    round, irq_valid, exp_valid, `CLIC_IP));
      if (exp_valid && irq_valid) begin
        chk(irq_id === exp_id[SrcW-1:0],
            $sformatf("round %0d: selected id %0d, reference says %0d",
                      round, irq_id, exp_id));
      end

      intr_src <= '0;
      quiesce();
    end
  endtask

  ///////////////
  // Main flow //
  ///////////////

  initial begin
    n_errors       = 0;
    n_checks       = 0;
    current_test   = "init";
    psel           = 1'b0;
    penable        = 1'b0;
    pwrite         = 1'b0;
    paddr          = '0;
    pwdata         = '0;
    intr_src       = '0;
    irq_ready      = 1'b0;
    kill_ack_en    = 1'b1;
    kill_ack_delay = 2;

    for (int unsigned i = 0; i < N_SOURCE; i++) begin
      cfg_ctl[i]  = '0;
      cfg_mode[i] = M_MODE;
      cfg_shv[i]  = 1'b0;
      cfg_le[i]   = 1'b0;
      cfg_ie[i]   = 1'b0;
      cfg_vsid[i] = '0;
      cfg_intv[i] = 1'b0;
    end
    for (int unsigned vs = 0; vs < MAX_VSCTXTS; vs++) cfg_vsprio[vs] = '0;
    cfg_mnlbits = 4'd8;
    cfg_nmbits  = 2'd2;

    @(posedge rst_n);
    repeat (5) @(posedge clk);

    test_edge_fires_once();
    test_level_deassert_during_ack();
    test_preempt_kill();
    test_priority_tie();
    test_zero_key_suppressed();
    test_vsprio_ordering();
    test_unmapped_addresses();
    test_priority_quiesced(20);

    repeat (20) @(posedge clk);

    $display("");
    $display("========================================");
    $display(" checks run : %0d", n_checks);
    $display(" errors     : %0d", n_errors);
    $display(" result     : %s", (n_errors == 0) ? "PASS" : "FAIL");
    $display("========================================");
    $display("");
    if (n_errors != 0) $fatal(1, "testbench failed");
    $finish;
  end

endmodule
