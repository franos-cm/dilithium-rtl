`timescale 1ns / 1ps

// Adapter so interface follows AXI-Stream protocol
module stream_adapter #(
    parameter w = 64
) (
    input  logic              clk,
    input  logic              rst,
    input  logic              start,
    input logic[1:0]          mode,
    input logic[2:0]          sec_lvl,

    // Coming from Dilithium
    input  logic           dilithium_valid_o,
    output logic           dilithium_ready_o,
    input  logic[w-1:0]    dilithium_data_o,

    // External IOs
    output logic           valid_o,
    input  logic           ready_o,
    output logic [w-1:0]   data_o,
    output logic           done,
    output logic           last // AXI-Stream LAST_T


);
    // Measured in words
    localparam int max_output_size = 932;
    localparam int max_output_width = $clog2(max_output_size);

    logic buffer_empty, output_last, output_done;
    logic last_word_in_buffer;
    logic [max_output_width - 1 : 0] output_size;


    // Buffer
    fifo_buffer #(
        .WIDTH(64),
        .DEPTH(max_output_size)
    ) buffer (
        .clk  (clk),
        .rst  (rst || start),
        .read_en (ready_o),
        .write_en (dilithium_valid_o),
        .data_in (dilithium_data_o),
        .data_out (data_o),
        .empty (buffer_empty),
        .last_word_in_buffer (last_word_in_buffer)
    );

    // Output size counter
    countern #(
        .WIDTH(max_output_width) 
    ) output_counter (
        .clk (clk),
        .rst (rst || start),
        .en (dilithium_valid_o),
        .load_max (start),
        .max_count(output_size),
        .count_last(output_last),
        .count_end(output_done)
    );

    latch dilithium_ready_in_latch (
        .clk (clk),
        .set (start),
        .rst (rst || (output_last && dilithium_valid_o)),
        .q   (dilithium_ready_o)
    );


    always_comb begin
        if (mode == 0)
            if (sec_lvl == 3'd2)
                output_size = 'd480;
            else if (sec_lvl == 3'd3)
                output_size = 'd744;
            else
                output_size = 'd932;
        else if (mode == 2'd1)
            output_size = 'd1;
        else
            if (sec_lvl == 3'd2)
                output_size = 'd303;
            else if (sec_lvl == 3'd3)
                output_size = 'd412;
            else
                output_size = 'd575;
    end;

    assign valid_o = !buffer_empty;
    assign done = output_done;
    assign last = output_done && last_word_in_buffer;

endmodule
