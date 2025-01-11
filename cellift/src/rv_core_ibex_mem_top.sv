// Copyright 2021 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Flavien Solt, ETH Zurich
// Date: 5th August 2021

module rv_core_ibex_mem_top import tlul_pkg::*; #(
  localparam int unsigned InstrMemAw = 30,
  localparam int unsigned DataMemAw  = 30,
  localparam type data_t = logic[31:0],
  localparam type strb_t = logic[31:0],
  localparam type addr_t = logic[InstrMemAw-1:0]
) (

  // Clock and Reset
  input  logic        clk_i,
  input  logic        rst_ni,
  // Clock domain for escalation receiver
  input  logic        clk_esc_i,
  input  logic        rst_esc_ni,

  input  logic        test_en_i,     // enable all clock gates for testing
  input  prim_ram_1p_pkg::ram_1p_cfg_t ram_cfg_i,

  input  logic [31:0] hart_id_i,
  input  logic [31:0] boot_addr_i,

  // Instruction memory interface
  output logic  instr_mem_req_o,
  input  logic  instr_mem_gnt_i,
  output addr_t instr_mem_addr_o,
  output data_t instr_mem_wdata_o,
  output strb_t instr_mem_strb_o,
  output logic  instr_mem_we_o,
  input  data_t instr_mem_rdata_i,

  // Data memory interface
  output logic  data_mem_req_o,
  input  logic  data_mem_gnt_i,
  output addr_t data_mem_addr_o,
  output data_t data_mem_wdata_o,
  output strb_t data_mem_strb_o,
  output logic  data_mem_we_o,
  input  data_t data_mem_rdata_i,

  // Interrupt inputs
  input  logic        irq_software_i,
  input  logic        irq_timer_i,
  input  logic        irq_external_i,

  // Escalation input for NMI
  input  prim_esc_pkg::esc_tx_t esc_tx_i,
  output prim_esc_pkg::esc_rx_t esc_rx_o,

  // Debug Interface
  input  logic        debug_req_i,

  // Crash dump information
  output ibex_pkg::crash_dump_t crash_dump_o,

  // CPU Control Signals
  input lc_ctrl_pkg::lc_tx_t lc_cpu_en_i,
  output logic        core_sleep_o
);

  tlul_pkg::tl_d2h_t tl_i_toibex;
  tlul_pkg::tl_h2d_t tl_i_fromibex;
  tlul_pkg::tl_d2h_t tl_d_toibex;
  tlul_pkg::tl_h2d_t tl_d_fromibex;

  // Our memories always have exactly 1 latency cycle.
  logic instr_rvalid_d, instr_rvalid_q;
  logic data_rvalid_d, data_rvalid_q;

  assign instr_rvalid_d = instr_mem_req_o & ~instr_mem_we_o;
  assign data_rvalid_d = data_mem_req_o & ~data_mem_we_o;

  always_ff @(posedge clk_i) begin
    if (~rst_ni) begin
      instr_rvalid_q <= '0;
      data_rvalid_q <= '0;
    end else begin
      instr_rvalid_q <= instr_rvalid_d;
      data_rvalid_q <= data_rvalid_d;
    end
  end

  // Instruction memory
  tlul_adapter_sram #(
    .SramAw(InstrMemAw),
    .SramDw(32), // Must be multiple of the TL width
    .Outstanding(1),         // Only one request is accepted
    .ByteAccess(1),          // 1: true, 0: false
    .ErrOnWrite(0),          // 1: Writes not allowed, automatically error
    .ErrOnRead(0),           // 1: Reads not allowed, automatically error
    .CmdIntgCheck(0),        // 1: Enable command integrity check
    .EnableRspIntgGen(1),    // 1: Generate response integrity
    .EnableDataIntgGen(0),   // 1: Generate response data integrity
    .EnableDataIntgPt(0)    // 1: Passthrough command/response data integrity
  ) i_instr_tlul_adapter_sram (
    .clk_i,
    .rst_ni,

    .tl_i(tl_i_fromibex),
    .tl_o(tl_i_toibex),
    .en_ifetch_i(InstrEn), //tl_instr_en_e::InstrEn

    // SRAM interface
    .req_o(instr_mem_req_o),
    .req_type_o(),
    .gnt_i(instr_mem_gnt_i),
    .we_o(instr_mem_we_o),
    .addr_o(instr_mem_addr_o),
    .wdata_o(instr_mem_wdata_o),
    .wmask_o(instr_mem_strb_o),
    .intg_error_o(),
    .rdata_i(instr_mem_rdata_i),
    .rvalid_i(instr_rvalid_q),
    .rerror_i(2'b0)
  );

  // Data memory
  tlul_adapter_sram #(
    .SramAw(DataMemAw),
    .SramDw(32), // Must be multiple of the TL width
    .Outstanding(1),         // Only one request is accepted
    .ByteAccess(1),          // 1: true, 0: false
    .ErrOnWrite(0),          // 1: Writes not allowed, automatically error
    .ErrOnRead(0),           // 1: Reads not allowed, automatically error
    .CmdIntgCheck(0),        // 1: Enable command integrity check
    .EnableRspIntgGen(1),    // 1: Generate response integrity
    .EnableDataIntgGen(0),   // 1: Generate response data integrity
    .EnableDataIntgPt(0)     // 1: Passthrough command/response data integrity
  ) i_data_tlul_adapter_sram (
    .clk_i,
    .rst_ni,

    .tl_i(tl_d_fromibex),
    .tl_o(tl_d_toibex),
    .en_ifetch_i(InstrEn), //tl_instr_en_e::InstrEn

    // SRAM interface
    .req_o(data_mem_req_o),
    .req_type_o(),
    .gnt_i(data_mem_gnt_i),
    .we_o(data_mem_we_o),
    .addr_o(data_mem_addr_o),
    .wdata_o(data_mem_wdata_o),
    .wmask_o(data_mem_strb_o),
    .intg_error_o(),
    .rdata_i(data_mem_rdata_i),
    .rvalid_i(data_rvalid_q),
    .rerror_i(2'b0)
  );


  rv_core_ibex i_rv_core_ibex (

    // Regular signals
    .clk_i,
    .rst_ni,
    .clk_esc_i,
    .rst_esc_ni,
    .test_en_i,
    .ram_cfg_i,
    .hart_id_i,
    .boot_addr_i,
    // Instruction memory interface
    .tl_i_o(tl_i_fromibex),
    .tl_i_i(tl_i_toibex),
    // Data memory interface
    .tl_d_o(tl_d_fromibex),
    .tl_d_i(tl_d_toibex),
    // Interrupt inputs
    .irq_software_i(irq_software_i),
    .irq_timer_i(irq_timer_i),
    .irq_external_i(irq_external_i),
    // Escalation input for NMI
    .esc_tx_i(esc_tx_i),
    .esc_rx_o(esc_rx_o),
    // Debug Interface
    .debug_req_i(debug_req_i),
    // Crash dump information
    .crash_dump_o(crash_dump_o),

    .lc_cpu_en_i(lc_cpu_en_i),
    .core_sleep_o(core_sleep_o)
  );

endmodule




