// Copyright 2022 Flavien Solt, ETH Zurich.
// Licensed under the General Public License, Version 3.0, see LICENSE for details.
// SPDX-License-Identifier: GPL-3.0-only

// Conservative ROM module with taints.

module taint_rom #(
  parameter logic [31:0] AddrOffset,
  parameter int ROM_ADDR_WIDTH = 15, // bits

  parameter int Width         = 32, // bit
  parameter int NumTaints     = 1,
  parameter int ByteAddressed = 0, // Whether the ROM is word-addressed or byte-addressed

  parameter bit PreloadELF = 1,
  parameter bit PreloadTaints = 1,

  // Derived parameters.
  localparam int AddrWidth  = ROM_ADDR_WIDTH,
  localparam int Depth      = 1 << AddrWidth,
  localparam int WidthBytes = Width >> 3
) (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         test_mode_i,
  input  logic         init_ni,
  input  logic [31:0]  wdata,
  input  logic [31:0]  add,
  input  logic         csn,
  input  logic         wen,
  input  logic [31:0]  be,
  input  logic [3:0]   id,
  output logic [31:0]  rdata,

  input  logic [NumTaints-1:0]         clk_i_t0,
  input  logic [NumTaints-1:0]         rst_ni_t0,
  input  logic [NumTaints-1:0]         test_mode_i_t0,
  input  logic [NumTaints-1:0]         init_ni_t0,
  input  logic [NumTaints-1:0] [31:0]  wdata_t0,
  input  logic [NumTaints-1:0] [31:0]  add_t0,
  input  logic [NumTaints-1:0]         csn_t0,
  input  logic [NumTaints-1:0]         wen_t0,
  input  logic [NumTaints-1:0] [31:0]  be_t0,
  input  logic [NumTaints-1:0] [3:0]   id_t0,
  output logic [NumTaints-1:0] [31:0]  rdata_t0
);

  initial begin
    assert(NumTaints == 1);
  end

  // For conservative IFT
  logic [NumTaints-1:0][Width-1:0] rdata_o_taint_before_conservative;
  for (genvar taint_id = 0; taint_id < NumTaints; taint_id++) begin : gen_taints_conservative
    logic was_req_addr_tainted_d, was_req_addr_tainted_q;
    assign was_req_addr_tainted_d = ((~csn) & |add_t0[taint_id]) | csn_t0[taint_id];
    always_ff @(posedge clk_i, negedge rst_ni) begin
      if (~rst_ni) begin
        was_req_addr_tainted_q <= '0;
      end else begin
        was_req_addr_tainted_q <= was_req_addr_tainted_d;
      end
    end

    // Taint the read data if the addr was tainted.
    assign rdata_t0[taint_id] = rdata_o_taint_before_conservative[taint_id] | {(Width){was_req_addr_tainted_q}};
  end

  import "DPI-C" function read_elf(input string filename);
  import "DPI-C" function byte get_section(output longint address, output longint len);
  import "DPI-C" context function byte read_section(input longint address, inout byte buffer[]);
  import "DPI-C" function string Get_BootROM_ELF_object_filename();
  import "DPI-C" function string Get_BootROM_TaintsPath();

  import "DPI-C" function init_taint_vectors(input longint num_taints);
  import "DPI-C" function read_taints(input string filename);
  import "DPI-C" function byte get_taint_section(input longint taint_id, output longint address, output longint len);
  import "DPI-C" context function byte read_taint_section(input longint taint_id, input longint address, inout byte buffer[]);

  localparam int unsigned BankId = 0;
  localparam int unsigned NumBanks = 1;

  logic [Width-1:0] memory [Depth];
  logic [31:0] word_addr;

  if (ByteAddressed) begin : gen_word_address
    assign word_addr = add[ROM_ADDR_WIDTH-1:0] >> 2; 
  end else begin 
    assign word_addr = add[ROM_ADDR_WIDTH-1:0]; 
  end

  //
  // DPI
  //
  int sections [bit [31:0]];

  localparam int unsigned PreloadBufferSize = 10000000;
  initial begin // Load the binary into memory.
    // Assume that all sections are aligned on NumBanks * WidthBytes
    if (PreloadELF) begin
      automatic string binary = Get_BootROM_ELF_object_filename(); // defaults to "../../../sw/boot_rom/boot_rom.o"
      longint section_addr, section_len;
      byte buffer[PreloadBufferSize];
      void'(read_elf(binary));
      $display("Preloading boot rom ELF with: %s (bank %d)", binary, BankId);
      while (get_section(section_addr, section_len)) begin
        automatic int num_words = (section_len+(WidthBytes-1))/WidthBytes;
        $display("Loading next section of size: %d words.", num_words);
        sections[section_addr/WidthBytes] = num_words;
        // buffer = new [num_words*WidthBytes];
        // assert(num_words*WidthBytes >= PreloadBufferSize);
        void'(read_section(section_addr, buffer));

        for (int i = 0; i < num_words; i++) begin
          automatic logic [WidthBytes-1:0][7:0] word = '0;
          for (int j = 0; j < WidthBytes; j++) begin
            word[j] = buffer[i*WidthBytes+j];
          end

          // Only write the word to the (right-shifted) memory if this corresponds to the right bank.
          if (AddrOffset <= section_addr/* && (((section_addr-AddrOffset)/WidthBytes+i)%NumBanks == BankId)*/) begin
            memory[((section_addr-AddrOffset)/WidthBytes+i)/NumBanks] = word;
            $display("Bank %d: loading addr/wbytes %x to boot rom addr %x: %x", BankId, section_addr/WidthBytes+i, ((section_addr-AddrOffset)/WidthBytes+i)/NumBanks, word);
          end
        end
      end
      $display("Done preloading boot rom ELF (bank %d).", BankId);
    end
  end

  //
  //  Data
  //

  always_ff @(posedge clk_i) begin
		if (csn == 0)
      rdata <= memory[word_addr];
  end

  //
  // Taint
  //

  logic [Width-1:0] mem_taints [bit [31:0]];

  initial begin // Load the taint into memory.
    if (PreloadTaints) begin
      automatic string binary = Get_BootROM_TaintsPath(); // defaults to  "../../../taint_data/boot_rom/boot_rom_taint_data.txt";
      longint section_addr, section_len;
      byte buffer[PreloadBufferSize];
      void'(init_taint_vectors(NumTaints));
      void'(read_taints(binary));
      $display("Preloading boot rom taints with: %s (bank %d) (offset %x)", binary, BankId, AddrOffset);
      for (int taint_id = 0; taint_id < NumTaints; taint_id++) begin : gen_load_taints
        while (get_taint_section(taint_id, section_addr, section_len)) begin
          automatic int num_words = (section_len+(WidthBytes-1))/WidthBytes;
          sections[section_addr/WidthBytes] = num_words;
          // assert(num_words*WidthBytes >= PreloadBufferSize);
          void'(read_taint_section(taint_id, section_addr, buffer));

          for (int i = 0; i < num_words; i++) begin
            automatic logic [WidthBytes-1:0][7:0] word = '0;
            for (int j = 0; j < WidthBytes; j++) begin
              word[j] = buffer[i*WidthBytes+j];
            end
            if (!mem_taints.exists(((section_addr-AddrOffset)/WidthBytes+i)/NumBanks))
              mem_taints[((section_addr-AddrOffset)/WidthBytes+i)/NumBanks] = {NumTaints*Width{1'b0}};

            // Only write the taint word to the (right-shifted) taint memory if this corresponds to the right bank.
            if (AddrOffset <= section_addr && (((section_addr-AddrOffset)/WidthBytes+i)%NumBanks == BankId)) begin
              mem_taints[((section_addr-AddrOffset)/WidthBytes+i)/NumBanks][taint_id] = word;
              $display("Bank %d: tainting addr/wbytes %x to boot rom addr %x: %x", BankId, section_addr/WidthBytes+i, ((section_addr-AddrOffset)/WidthBytes+i)/NumBanks, word);
            end
          end
        end
      end
      $display("Done preloading boot rom taints (bank %d).", BankId);
    end
  end

  for (genvar taint_id = 0; taint_id < NumTaints; taint_id++) begin : gen_rdata_taints
    always_ff @(posedge clk_i) begin
      if (csn == 0)
        if (mem_taints.exists(word_addr))
          rdata_o_taint_before_conservative[taint_id] <= mem_taints[word_addr];
        else
          rdata_o_taint_before_conservative[taint_id] <= '0;
    end
  end

endmodule
