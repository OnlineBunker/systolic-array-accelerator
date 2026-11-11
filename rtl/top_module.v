// ============================================================================
// top_module.v
// 4x4 systolic-array matrix-multiplication accelerator, C = A x B.
// Operands: signed Q8.8 (16 bit). Accumulators: full precision, 34 bit.
// ============================================================================
`timescale 1ns/1ps
module top_module #(
    parameter N     = 4,
    parameter DW    = 16,
    parameter FRAC  = 8,
    parameter ACC_W = 2*DW + $clog2(N),
    parameter AW    = $clog2(N*N),
    parameter SW    = $clog2(2*N)
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     start,
    // load port
    input  wire                     wr_en,
    input  wire                     wr_sel,     // 0 = A, 1 = B
    input  wire [AW-1:0]            wr_addr,
    input  wire [DW-1:0]            wr_data,
    // result port
    input  wire [AW-1:0]            rd_addr,
    output wire signed [ACC_W-1:0]  rd_raw,
    output wire signed [DW-1:0]     rd_q88,
    output wire                     rd_ovf,
    // status
    output wire                     busy,
    output wire                     done
);
    wire          clr, array_en, feed_en, capture;
    wire [SW-1:0] step;
    wire          a_we, b_we;
    wire [AW-1:0] buf_addr;
    wire [DW-1:0] buf_data;

    wire [N*DW-1:0]        a_left, b_top;
    wire [N-1:0]           va_left, vb_top;
    wire [N*N*ACC_W-1:0]   acc_flat, result;

    systolic_controller #(.N(N), .SW(SW)) u_ctrl (
        .clk(clk), .rst(rst), .start(start),
        .clr(clr), .array_en(array_en), .feed_en(feed_en), .step(step),
        .capture(capture), .busy(busy), .done(done)
    );

    matrix_interface #(.N(N), .DW(DW), .ACC_W(ACC_W), .FRAC(FRAC), .AW(AW)) u_if (
        .busy(busy),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_addr(wr_addr), .wr_data(wr_data),
        .a_we(a_we), .b_we(b_we), .buf_addr(buf_addr), .buf_data(buf_data),
        .rd_addr(rd_addr), .result(result),
        .rd_raw(rd_raw), .rd_q88(rd_q88), .rd_ovf(rd_ovf)
    );

    input_buffer #(.N(N), .DW(DW), .ROWWISE(1), .AW(AW), .SW(SW)) u_buf_a (
        .clk(clk), .rst(rst), .we(a_we), .waddr(buf_addr), .wdata(buf_data),
        .feed_en(feed_en), .step(step), .data_out(a_left), .valid_out(va_left)
    );

    input_buffer #(.N(N), .DW(DW), .ROWWISE(0), .AW(AW), .SW(SW)) u_buf_b (
        .clk(clk), .rst(rst), .we(b_we), .waddr(buf_addr), .wdata(buf_data),
        .feed_en(feed_en), .step(step), .data_out(b_top), .valid_out(vb_top)
    );

    systolic_array #(.N(N), .DW(DW), .ACC_W(ACC_W)) u_array (
        .clk(clk), .rst(rst), .clr(clr), .en(array_en),
        .a_left(a_left), .va_left(va_left),
        .b_top(b_top), .vb_top(vb_top),
        .acc_flat(acc_flat)
    );

    output_register #(.N(N), .ACC_W(ACC_W)) u_out (
        .clk(clk), .rst(rst), .capture(capture),
        .acc_in(acc_flat), .result(result)
    );
endmodule
