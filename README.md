# RISC-V CLIC
RISC-V Core Local Interrupt Controller (CLIC) is an interrupt controller for
RISC-V cores subsuming the original RISC-V local interrupt scheme (CLINT). It
promises pre-emptive, low-latency, vectored, priority/level based interrupts.

This IP is meant to be used together with a suitably modified version of a core.
Currently, a modified version of the
[CV32E40P](https://github.com/openhwgroup/cv32e40p) is supported.

[Here](./doc/clic.adoc) is the detailed specification this IP is based on. For
the upstream specification visit
[this](https://github.com/riscv/riscv-fast-interrupt/blob/master/clic.adoc)
link.

Note that this IP is based on an intermediate development version of the CLIC
specification which will still change substantially. This IP will try to track
the changes of the specification. The [specification document](./doc/clic.adoc)
in this repository is a snapshot of the upstream specification and the version
this IP is based on.

## Features

- RISC-V Core Local Interrupt Controller (CLIC) compliant interrupt controller
- Support up to 4096 interrupt lines
- Support up to 8 bits of priority/level information per interrupt line
- Supports (a modified) [CV32E40P](#CLIC-and-CV32E40P)

## Parametrization
Some parameters are configurable. See the marked variables in the table below.

```
Name             Value Range                   Description
CLICANDBASIC     0-1     (depends on core)     Implements original basic mode also?
CLICPRIVMODES    1-3     (depends on core)     Number privilege modes: 1=M, 2=M/U,
                                                                       3=M/S/U
CLICLEVELS       2-256                         Number of interrupt levels including 0
*NUM_INTERRUPT*  4-4096  (default=256)         Always has MSIP, MTIP, MEIP, CSIP
CLICMAXID        12-4095                       Largest interrupt ID
*CLICINTCTLBITS* 0-8     (default=8)           Number of bits implemented in
                                               clicintctl[i]
CLICCFGMBITS     0-ceil(lg2(CLICPRIVMODES))    Number of bits implemented for
                                               cliccfg.nmbits
CLICCFGLBITS     0-ceil(lg2(CLICLEVELS))       Number of bits implemented for
                                               cliccfg.nlbits
CLICSELHVEC      0-1     (0-1)                 Selective hardware vectoring supported?
CLICMTVECALIGN   6-13    (depends on core)     Number of hardwired-zero least
                                               significant bits in mtvec address.
CLICXNXTI        0-1     (depends on core)     Has xnxti CSR implemented?
CLICXCSW         0-1     (depends on core)     Has xscratchcsw/xscratchcswl
                                               implemented?
```

## Integration and Dependencies
This IP requires

- [common_cells](https://github.com/pulp-platform/common_cells)

and a suitably modified core (see sections below).

The [bender](https://github.com/pulp-platform/bender) and legacy
[IPApproX](https://github.com/pulp-platform/IPApproX) flow are supported.

`clic.sv` is an APB4 device: it exposes `psel_i`, `penable_i`, `pwrite_i`,
`pprot_i`, `paddr_i`, `pwdata_i`, `pstrb_i`, `pready_o`, `prdata_o` and
`pslverr_o` directly, and there is no separate bus wrapper. Byte strobes are
honoured, so sub-word writes work.


## CLIC and CV32E40P
The patch required to use the CV32E40P together with the CLIC lives in this
[branch](https://github.com/pulp-platform/cv32e40p/tree/clic). The CLIC mode is
an elaboration time parameter at this moment, but will support a dynamic switch
at some point.

Here is the summary
```
Name             Value
CLICANDBASIC     0   (dynamic mode under development)
CLICPRIVMODES    2
NUM_INTERRUPT    32-256
CLICINTCTLBITS   0-8
CLICSELHVEC      1
CLICMTVECALIGN   8
CLICXNXTI        0   (partial, under development)
CLICXCSW         1
```

## CLIC and CVA6
Not supported yet.

## FreeRTOS Support
There is very basic support for the CLIC in
[pulp-freertos](https://github.com/pulp-platform/pulp-freertos) with more a more
complete level/priority implementation in the works.

## Register interface
The CLIC's register files are generated with
[PeakRDL-regblock](https://github.com/SystemRDL/PeakRDL-regblock) from the
SystemRDL descriptions in `rdl/`, and are checked into `src/`, so by default
they require no attention of the user.

`rdl/clic_regs.rdl` defines the register *types* and instantiates nothing, so
the bit layout of every register exists in exactly one place. Everything else
only chooses how to instantiate those types:

- the four leaf wrappers put one register at offset 0 and are fed to
  `peakrdl regblock` to produce the RTL in `src/`;
- `rdl/clic.rdl` puts the same types at their real addresses to describe the
  software-visible memory map, and is never fed to `regblock`.

Each leaf wrapper yields one module, instantiated as follows:

- `cliccfg.rdl` -> `cliccfg_reg`, instantiated once. This is the `cliccfg`
  register of the specification; the decoder aliases the single instance into
  both the M-mode window (`0x0000`) and the S-mode window (`0x8000`), which is
  why it is not named after either privilege mode.
- `clicint.rdl` -> `clicint_reg`, one instance per interrupt line. The field bit
  positions match the specification's four byte-wide registers: `clicintip` at
  bit 0, `clicintie` at bit 8, `clicintattr` at bits 23:16 and `clicintctl` at
  bits 31:24.
- `clicintv.rdl` -> `clicintv_reg`, one instance per four interrupt lines
  (vCLIC extension, not part of the specification snapshot in `doc/`).
- `clicvs.rdl` -> `clicvs_reg`, one instance per four VS contexts (likewise a
  vCLIC extension).

To regenerate them after editing a `.rdl` file:

```console
    make regs
```

PeakRDL is pinned in `pyproject.toml` and provisioned by
[uv](https://docs.astral.sh/uv/) on demand, so no manual setup is needed. The
generated blocks are written straight into `src/`, where `Bender.yml` and
`src_files.yml` pick them up.

Note that the number of interrupt lines is not baked into the generated
register files: each leaf `.rdl` describes a single 32-bit register, the CLIC
instantiates one such block per interrupt line, and the whole array scales with
the `N_SOURCE` parameter of `clic.sv`. The RTL blocks therefore carry no
elaboration-time parameters, and regenerating them never depends on how the IP
is configured. Only the software views do.

### Using this from a superproject
The memory-map export rules live in `clic.mk`, which is meant to be imported:

```make
    CLIC_ROOT ?= $(shell bender path clic)
    include $(CLIC_ROOT)/clic.mk
```

It provides two targets, both views of the same memory map:

- `clic-hdr` writes a C header to `$(CLIC_HDR)`.
- `clic-defs` writes a SystemVerilog `` `define `` header to `$(CLIC_DEFS)`.

Neither is checked in, because both depend on how the IP is configured. Set
`CLIC_NUM_SOURCES`, `CLIC_NUM_VSCTXTS` and `CLIC_VSCLIC` to match your
instantiation and point `CLIC_HDR` / `CLIC_DEFS` wherever you want the output.

`PEAKRDL` defaults to a bare `peakrdl` on `PATH`, as in `cheshire.mk` and
`clint.mk`: the importing project supplies the tool, so everything it generates
comes from one PeakRDL rather than this IP quietly running a second one. To use
the version pinned here instead, set
`PEAKRDL := uv run --project $(CLIC_ROOT) --group regs peakrdl`.

There is deliberately no RTL generation target in the fragment. The register
blocks take no elaboration-time parameters, so they are identical for every
configuration and are checked into `src/`: a superproject consumes them through
Bender and never regenerates them. `make regs` in this repository's top-level
Makefile covers that, and is only needed when a `.rdl` file changes.

To pull the register definitions into a larger address map instead, include
`rdl/clic_regs.rdl` (for the register types) or `rdl/clic.rdl` (for the whole
CLIC map) from your own SystemRDL and pass `-I $(CLIC_ROOT)/rdl`. Both files
are include-guarded. This is how a SoC-level address map can describe the CLIC
without restating any of its registers.

This repository eats its own dog food: `tb_clic.sv` takes every register
address from a generated `clic_reg_defs.svh` rather than restating them, so a
disagreement between `rdl/clic.rdl` and the decoder in `clic.sv` shows up as a
test failure.

### What is deliberately not in the register description
SystemRDL has no notion of the address window an access arrived through, so
everything that depends on it lives in the decoder in `clic.sv` rather than in
the generated blocks:

- the same `clicint` storage is aliased into the M-mode window, the S-mode
  window and one window per VS context;
- whether an access is permitted depends on the *contents* of other registers
  (`attr_mode`, and for the VS windows also the `v` and `vsid` fields), so an
  S-mode or VS-mode access to a line above its privilege is dropped and reads
  back as zero;
- `clicint` bit 23 is forced low outside the M-mode window, so a line cannot be
  promoted to M-mode from a less privileged window.

This was equally true of the previous regtool-based flow; the register
generator never owned any of it.

## Directory Structure
```
.
├── doc      CLIC spec, Blockdiagrams
├── rdl      Register map descriptions (SystemRDL)
├── src      RTL, including the generated register blocks
├── test     Testbench
├── clic.mk  Register generation rules, importable by a superproject
```

## License
This project is licensed under a mix of Apache 2.0 and the Solderpad Hardware
License 0.51, with the applicable license recorded in each file's
`SPDX-License-Identifier` tag. Full texts are in `LICENSES/`.

- **Apache 2.0** covers everything derived from lowRISC sources (`clic.sv`,
  `clic_gateway.sv`, `clic_target.sv`, which carry the lowRISC copyright and
  are upstream Apache 2.0), the register blocks generated from `rdl/`, the
  SystemRDL descriptions themselves, and all build and tooling files.
- **Solderpad 0.51** covers the hardware written entirely at ETH Zurich and the
  University of Bologna (`clic_pkg.sv`, `clic_reg_adapter.sv`, `tb_clic.sv`).

The root `LICENSE` file remains Apache 2.0, which is the license of the
majority of the project and of the lowRISC code it builds on.
