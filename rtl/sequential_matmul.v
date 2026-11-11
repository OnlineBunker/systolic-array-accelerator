// ============================================================================
// sequential_matmul.v  (baseline for comparison)
// Same arithmetic as the systolic design but with a single MAC unit that
// walks i, j, k sequentially: one multiply-accumulate per clock.
// Same load/read interface as top_module.
// ============================================================================
`timescale 1ns/1ps
module sequential_matmul #(
    parameter N     = 4,
    parameter DW    = 16,
    parameter ACC_W = 2*DW + $clog2(N),
    parameter AW    = $clog2(N*N),
    parameter IW    = $clog2(N)
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     start,
    input  wire                     wr_en,
    input  wire                     wr_sel,
    input  wire [AW-1:0]            wr_addr,
    input  wire [DW-1:0]            wr_data,
    input  wire [AW-1:0]            rd_addr,
    output wire signed [ACC_W-1:0]  rd_raw,
    output wire                     busy,
    output reg                      done
);
    reg signed [DW-1:0]    A [0:N*N-1];
    reg signed [DW-1:0]    B [0:N*N-1];
    reg signed [ACC_W-1:0] C [0:N*N-1];

    reg running;
    reg [IW-1:0] i, j, k;
    reg signed [ACC_W-1:0] acc;

    assign busy   = running;
    assign rd_raw = C[rd_addr];

    always @(posedge clk) begin
        if (wr_en && !running) begin
            if (wr_sel) B[wr_addr] <= wr_data;
            else        A[wr_addr] <= wr_data;
        end
    end

    wire signed [2*DW-1:0]  prod = A[i*N + k] * B[k*N + j];
    wire signed [ACC_W-1:0] sum  = acc + {{(ACC_W-2*DW){prod[2*DW-1]}}, prod};

    always @(posedge clk) begin
        if (rst) begin
            running <= 1'b0; done <= 1'b0;
            i <= 0; j <= 0; k <= 0; acc <= 0;
        end else if (!running) begin
            if (start) begin
                running <= 1'b1; done <= 1'b0;
                i <= 0; j <= 0; k <= 0; acc <= 0;
            end
        end else begin
            if (k == N-1) begin
                C[i*N + j] <= sum;
                acc <= 0;
                k   <= 0;
                if (j == N-1) begin
                    j <= 0;
                    if (i == N-1) begin
                        running <= 1'b0; done <= 1'b1;
                    end else i <= i + 1'b1;
                end else j <= j + 1'b1;
            end else begin
                acc <= sum;
                k   <= k + 1'b1;
            end
        end
    end
endmodule
