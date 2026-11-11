// ============================================================================
// matrix_interface.v
// Host-side port of the accelerator.
//   Write: wr_en, wr_sel (0 = A, 1 = B), wr_addr (r*N + c), wr_data (Q8.8).
//          Writes are ignored while the accelerator is busy.
//   Read : rd_addr selects C[r][c] (combinational read of the output register)
//          rd_raw  : full-precision accumulator (Q.16 fractional bits)
//          rd_q88  : result rounded to nearest and saturated to Q8.8
//          rd_ovf  : 1 when rd_q88 was saturated
// ============================================================================
`timescale 1ns/1ps
module matrix_interface #(
    parameter N     = 4,
    parameter DW    = 16,
    parameter ACC_W = 34,
    parameter FRAC  = 8,
    parameter AW    = $clog2(N*N)
)(
    input  wire                     busy,
    // host write port
    input  wire                     wr_en,
    input  wire                     wr_sel,
    input  wire [AW-1:0]            wr_addr,
    input  wire [DW-1:0]            wr_data,
    // to input buffers
    output wire                     a_we,
    output wire                     b_we,
    output wire [AW-1:0]            buf_addr,
    output wire [DW-1:0]            buf_data,
    // host read port
    input  wire [AW-1:0]            rd_addr,
    input  wire [N*N*ACC_W-1:0]     result,
    output wire signed [ACC_W-1:0]  rd_raw,
    output reg  signed [DW-1:0]     rd_q88,
    output reg                      rd_ovf
);
    assign a_we     = wr_en & ~busy & ~wr_sel;
    assign b_we     = wr_en & ~busy &  wr_sel;
    assign buf_addr = wr_addr;
    assign buf_data = wr_data;

    // Read mux written with constant part-selects only. (An earlier version
    // used result[rd_addr*ACC_W +: ACC_W]; synthesis turned the variable
    // multiply into a DSP block plus a 544-bit barrel shifter.)
    reg [ACC_W-1:0] rd_mux;
    integer m;
    always @(*) begin
        rd_mux = {ACC_W{1'b0}};
        for (m = 0; m < N*N; m = m + 1)
            if (rd_addr == m) rd_mux = result[m*ACC_W +: ACC_W];
    end
    assign rd_raw = rd_mux;

    // Q(.2*FRAC) -> Q(.FRAC): add half LSB, arithmetic shift, saturate
    localparam SW_ = ACC_W + 1;
    // NOTE: a concatenation is always unsigned in Verilog, so the sign
    // extension is placed in a signed net before the arithmetic shift.
    wire signed [SW_-1:0] ext     = {rd_raw[ACC_W-1], rd_raw};
    wire signed [SW_-1:0] rounded = (ext + (1 <<< (FRAC-1))) >>> FRAC;
    localparam signed [SW_-1:0] MAXV =  (1 <<< (DW-1)) - 1;
    localparam signed [SW_-1:0] MINV = -(1 <<< (DW-1));

    always @(*) begin
        if (rounded > MAXV) begin
            rd_q88 = MAXV[DW-1:0]; rd_ovf = 1'b1;
        end else if (rounded < MINV) begin
            rd_q88 = MINV[DW-1:0]; rd_ovf = 1'b1;
        end else begin
            rd_q88 = rounded[DW-1:0]; rd_ovf = 1'b0;
        end
    end
endmodule
