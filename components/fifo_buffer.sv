`timescale 1ns / 1ps


module fifo_buffer #(
    parameter int WIDTH,
    parameter int DEPTH
) (
    input  logic              clk,
    input  logic              rst,
    input  logic              read_en,
    input  logic              write_en,
    input  logic[WIDTH-1:0]   data_in,
    output logic[WIDTH-1:0]   data_out,
    output logic              full,
    output logic              last_word_in_buffer,
    output logic              empty
);
    localparam ADDR_WIDTH = $clog2(DEPTH);

    logic [WIDTH-1:0] buffer_data [DEPTH-1:0];
    logic [ADDR_WIDTH-1:0] read_address, write_address;
    // NOTE: we could avoid having counter by having one extra bit in the adresses, but the
    // update logic for the adresses gets more complex... this solution is more intuitive.
    logic [ADDR_WIDTH:0] counter, updated_counter;

    always_ff @(posedge clk) begin
        
    
        if (rst) begin
            read_address <= 0;
            write_address <= 0;
            updated_counter = 0;
        end
        else begin
            updated_counter = counter;
            if (write_en && !full) begin
                buffer_data[write_address] <= data_in;
                write_address <= (write_address == DEPTH-1) ? 0 : write_address + 1;
                updated_counter = updated_counter + 1;
            end
            if (read_en && !empty) begin
                read_address <= (read_address == DEPTH-1) ? 0 : read_address + 1;
                updated_counter = updated_counter - 1;
            end
        end

        // Note non blocking statements for updated_counter
        counter <= updated_counter;
    end

    assign data_out = buffer_data[read_address];
    assign empty = (counter == 0);
    assign last_word_in_buffer = (counter == 'd1);
    assign full  = (counter == DEPTH);
endmodule