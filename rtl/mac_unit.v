// ============================================================================
// mac_unit.v
// Two-stage pipelined signed multiply-accumulate unit.
//   stage 1: prod_r <= a * b             (maps onto the FPGA multiplier's
//            acc_en_r <= en               output register)
//   stage 2: acc <= acc + prod_r          when acc_en_r = 1
// Operands are Q8.8 (DW = 16); the product is Q16.16 and the accumulator
// keeps full precision. ACC_W = 2*DW + clog2(N) guarantees that a sum of N
// products can never overflow, for any input values.
// The product register removes the multiplier from the adder's timing path
// (ECP5 post-route Fmax 97.2 MHz -> see docs/performance_analysis.md).
// ============================================================================
`timescale 1ns/1ps
module mac_unit #(
    parameter DW    = 16,
    parameter ACC_W = 34
)(
    input  wire                     clk,
    input  wire                     rst,    // synchronous, active-high
    input  wire                     clr,    // synchronous clear
    input  wire                     en,     // accumulate this operand pair
    input  wire signed [DW-1:0]     a,
    input  wire signed [DW-1:0]     b,
    output wire signed [2*DW-1:0]   prod,   // combinational product (debug view)
    output reg  signed [ACC_W-1:0]  acc
);
    assign prod = a * b;

    reg signed [2*DW-1:0] prod_r;
    reg                   acc_en_r;

    always @(posedge clk) begin
        if (rst || clr) begin
            prod_r   <= {2*DW{1'b0}};
            acc_en_r <= 1'b0;
            acc      <= {ACC_W{1'b0}};
        end else begin
            prod_r   <= prod;
            acc_en_r <= en;
            if (acc_en_r)
                acc <= acc + {{(ACC_W-2*DW){prod_r[2*DW-1]}}, prod_r};
        end
    end
endmodule
