`timescale 1ns / 1ps

module edge_detector (
    input  logic clk,
    input  logic signal_in,
    output logic rising_edge,
    output logic falling_edge
);
    logic prev_signal;

    always_ff @(posedge clk) begin
        prev_signal <= signal_in;
    end

    assign rising_edge = signal_in & ~prev_signal;
    assign falling_edge = (~signal_in) & prev_signal;

endmodule
