// ============================================================================
// processing_element.v
// One cell of the output-stationary systolic array.
//   * MACs a_in * b_in into its local accumulator when both operands are valid
//   * forwards A (and its valid bit) to the right neighbour, one cycle later
//   * forwards B (and its valid bit) to the neighbour below, one cycle later
// ============================================================================
`timescale 1ns/1ps
module processing_element #(
    parameter DW    = 16,
    parameter ACC_W = 34
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     clr,     // clear accumulator + pipeline
    input  wire                     en,      // global enable / stall
    input  wire signed [DW-1:0]     a_in,
    input  wire signed [DW-1:0]     b_in,
    input  wire                     va_in,
    input  wire                     vb_in,
    output reg  signed [DW-1:0]     a_out,
    output reg  signed [DW-1:0]     b_out,
    output reg                      va_out,
    output reg                      vb_out,
    output wire signed [2*DW-1:0]   prod,
    output wire signed [ACC_W-1:0]  acc
);
    mac_unit #(.DW(DW), .ACC_W(ACC_W)) u_mac (
        .clk (clk),
        .rst (rst),
        .clr (clr),
        .en  (en & va_in & vb_in),
        .a   (a_in),
        .b   (b_in),
        .prod(prod),
        .acc (acc)
    );

    always @(posedge clk) begin
        if (rst || clr) begin
            a_out  <= {DW{1'b0}};
            b_out  <= {DW{1'b0}};
            va_out <= 1'b0;
            vb_out <= 1'b0;
        end else if (en) begin
            a_out  <= a_in;
            b_out  <= b_in;
            va_out <= va_in;
            vb_out <= vb_in;
        end
    end
endmodule
