// Copyright 2022 Flavien Solt, ETH Zurich.
// Licensed under the General Public License, Version 3.0, see LICENSE for details.
// SPDX-License-Identifier: GPL-3.0-only

// ROM module without taints.

module notaint_rom #(
  parameter logic [31:0] AddrOffset,
  parameter int ROM_ADDR_WIDTH = 15, // bits

  parameter int Width         = 32, // bit
  parameter int ByteAddressed = 0, // Whether the ROM is word-addressed or byte-addressed

  parameter bit PreloadELF = 1,

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
  output logic [31:0]  rdata
);

  import "DPI-C" function read_elf(input string filename);
  import "DPI-C" function byte get_section(output longint address, output longint len);
  import "DPI-C" context function byte read_section(input longint address, inout byte buffer[]);
  import "DPI-C" function string Get_BootROM_ELF_object_filename();

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

endmodule
