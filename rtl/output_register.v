// ============================================================================
// output_register.v
// Captures all N*N accumulators in one clock when 'capture' is asserted and
// holds them stable for read-out while the array starts the next job.
// ============================================================================
`timescale 1ns/1ps
module output_register #(
    parameter N     = 4,
    parameter ACC_W = 34
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  capture,
    input  wire [N*N*ACC_W-1:0]  acc_in,
    output reg  [N*N*ACC_W-1:0]  result
);
    always @(posedge clk) begin
        if (rst)
            result <= {N*N*ACC_W{1'b0}};
        else if (capture)
            result <= acc_in;
    end
endmodule
