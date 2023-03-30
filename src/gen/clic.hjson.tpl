// Copyright 2022 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// SPDX-License-Identifier: Apache-2.0

# CLIC register template
# - src: Number of interrupt sources
{

  name: "CLIC",
  clock_primary: "clk_i",
  bus_interfaces: [
    { protocol: "reg_iface", direction: "device" }
  ],

  param_list: [
    { name: "NumSrc",
      desc: "Number of interrupt sources",
      type: "int",
      default: "${src}",
      local: "true"
    },
    { name: "ClicIntCtlBits",
      desc: "Number of interrupt control bits",
      type: "int",
      default: "${intctlbits}",
      local: "true"
    },
  ],

  regwidth: "32",
  registers: [
    { name: "CLICCFG",
      desc: "CLIC Configuration",
      swaccess: "rw",
      hwaccess: "hro",
      fields: [
        { bits: "31:7", name: "reserved", desc: "reserved", swaccess: "ro", hwaccess: "none" },  # workaround for full 32-bit access
        { bits: "6:5", name: "nmbits", desc: "number of privilege mode bits" },
        { bits: "4:1", name: "nlbits", desc: "number of interrupt level bits" },
        { bits: "0", name: "nvbits",
          desc: "indicates whether selective hardware vectoring is supported" },
      ],
    },
    { name: "CLICINFO",
      desc: "CLIC Information",
      swaccess: "ro",
      hwaccess: "hro",
      fields: [
        //{ bits: "31", name: "reserved" },
        { bits: "30:25", name: "num_trigger",
    desc: "number of maximum interrupt triggers supported" },
        { bits: "24:21", name: "CLICINTCTLBITS",
    desc: "number of bits implemented in clicintctl" },
        { bits: "20:13", name: "version",
    desc: "architecture version [20:17] and implementation version [16:13]" },
        { bits: "12:0", name: "num_interrupt",
    desc: "number of maximum interrupt inputs supported" },
      ],
    },
    { skipto: "0x1000" }
    { multireg:
      { name: "CLICINT",
	desc: "CLIC interrupt pending, enable, attribute and control",
	count: "256",
	cname: "CLIC",
	swaccess: "rw",
	hwaccess: "hro",
	fields: [
          { bits: "31:24", name: "CTL", desc: "interrupt control for interrupt" },
          { bits: "23:22", name: "ATTR_MODE", desc: "privilege mode of this interrupt" },
          //{ bits: "21:19", name: "reserved" },
          { bits: "18:17", name: "ATTR_TRIG", desc: "specify trigger type for this interrupt" },
          { bits: "16", name: "ATTR_SHV", desc: "enable hardware vectoring for this interrupt" },

          { bits: "7", name: "IE", desc: "interrupt enable for interrupt" },

          { bits: "0", name: "IP", desc: "interrupt pending for interrupt", hwaccess: "hrw" },
	],
      }
    },
  ]
}
