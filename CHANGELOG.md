# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.0.0] - 2025-09-22
### Added
- VS mode support through custom virtualization extension (vCLIC)
- Github CI setup (linting)

### Fixed
- Licenses update

## [2.0.0] - 2023-05-28
### Added
- Design is now parametrizable through SystemVerilog without requiring an
  intermediate codegen step through python
- Kill handshake logic. Core and CLIC can now work together to allow higher
  level interrupts to overtake current interrupts that used to be stuck in a
  handshake.
- S-mode support

### Changed
- Aligned to latest spec draft
- Memory map now follows the current clic draft (ie, ip, attr, ctrl)

### Fixed
- Blocking assignments
- Missing signal declarations

## [1.0.1] - 2022-02-15
### Fixed
- Bender.yml wrong register_interface git address

## [1.0.0] - 2022-02-03

### Added
- Initial version of RISC-V Core Local Interrupt Controller (CLIC)
