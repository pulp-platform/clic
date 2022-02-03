# RISC-V CLIC
RISC-V Core Local Interrupt Controller (CLIC) is a standardized interrupt
controller for RISC-V cores subsuming the original RISC-V local interrupt scheme
(CLINT). It promises pre-emptive, low-latency, vectored, priority/level based
interrupts.

This IP is meant to be used together with a suitably modified version of a core.
Currently, a modified version of the
[CV32E40P](https://github.com/openhwgroup/cv32e40p) is supported.

See [clic.adoc](./doc/clic.adoc) for the detailed specification this IP is based
on. The specification version in this repository reflects the version this IP is
based on. For the upstream specification visit
[this](https://github.com/riscv/riscv-fast-interrupt/blob/master/clic.adoc)
link.

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
- [register_interface](https://github.com/pulp-platform/register_interface)

and a suitably modified core (see sections below).

The [bender](https://github.com/pulp-platform/bender) and legacy
[IPApproX](https://github.com/pulp-platform/IPApproX) flow are supported.

Besides the native
[register_interface](https://github.com/pulp-platform/register_interface) there
is an APB wrapper available.


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
By default the CLIC's register file is manually written requiring no attention
of the user.

Alternatively, [regtool](https://docs.opentitan.org/doc/rm/register_tool/) can
be used to generate the register file. For that, go to `src/gen/` and call `make
all` with the environment variable `REGTOOL` pointing to `regtool.py` of the
[register_interface](https://github.com/pulp-platform/register_interface)
repository and `NUM_INTERRUPT` and `CLICINTCTLBITS` appropriately set. Finally,
make sure your `src_files.yml` or `Bender.yml` points to

- `src/gen/clic_reg_pkg.sv`
- `src/gen/clic_reg_top.sv`
- `src/gen/clic_reg_adapater.sv`

`regtool` has various limitations on how the register map can look like,
requiring the memory map description (`src/gen/clic.hjson`) to be derived from a
template (`src/gen/clic.hjson.tpl`), resulting in rather unwieldy code and
documentation.

## Directory Structure
```
.
├── doc      CLIC spec, Blockdiagrams
├── src      RTL
├── src/gen  Templates and python scripts
```

## License
This project uses sourcecode from lowRISC licensed under Apache 2.0. The changes
and additions are being made available using Apache 2.0 see LICENSE for more
details.
