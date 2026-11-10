// ============================================================================
// input_buffer.v
// Stores one N x N matrix (row-major address = r*N + c) and streams it into
// one edge of the systolic array with the diagonal skew the array needs.
//
//   ROWWISE = 1 (matrix A): lane l carries row l,    element A[l][k]
//   ROWWISE = 0 (matrix B): lane l carries column l, element B[k][l]
//
// At feed step s, lane l outputs element k = s - l when 0 <= k < N,
// otherwise zero with valid = 0. Output is registered (1 cycle latency).
// ============================================================================
`timescale 1ns/1ps
module input_buffer #(
    parameter N       = 4,
    parameter DW      = 16,
    parameter ROWWISE = 1,
    parameter AW      = $clog2(N*N),
    parameter SW      = $clog2(2*N)
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              we,
    input  wire [AW-1:0]     waddr,
    input  wire [DW-1:0]     wdata,
    input  wire              feed_en,
    input  wire [SW-1:0]     step,
    output reg  [N*DW-1:0]   data_out,
    output reg  [N-1:0]      valid_out
);
    reg [DW-1:0] mem [0:N*N-1];

    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
    end

    integer l;
    always @(posedge clk) begin
        if (rst) begin
            data_out  <= {N*DW{1'b0}};
            valid_out <= {N{1'b0}};
        end else begin
            for (l = 0; l < N; l = l + 1) begin
                if (feed_en && (step >= l) && (step < l + N)) begin
                    data_out[l*DW +: DW] <= ROWWISE ? mem[l*N + (step - l)]
                                                    : mem[(step - l)*N + l];
                    valid_out[l] <= 1'b1;
                end else begin
                    data_out[l*DW +: DW] <= {DW{1'b0}};
                    valid_out[l] <= 1'b0;
                end
            end
        end
    end
endmodule
