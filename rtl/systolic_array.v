// ============================================================================
// systolic_array.v
// N x N grid of processing elements (output-stationary dataflow).
//   Row i of A enters PE(i,0) from the left and moves right.
//   Column j of B enters PE(0,j) from the top and moves down.
//   PE(i,j) ends up holding C[i][j] = sum_k A[i][k] * B[k][j].
// Buses are flattened so the module is plain Verilog-2001.
// ============================================================================
`timescale 1ns/1ps
module systolic_array #(
    parameter N     = 4,
    parameter DW    = 16,
    parameter ACC_W = 34
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    clr,
    input  wire                    en,
    input  wire [N*DW-1:0]         a_left,    // lane i -> row i
    input  wire [N-1:0]            va_left,
    input  wire [N*DW-1:0]         b_top,     // lane j -> column j
    input  wire [N-1:0]            vb_top,
    output wire [N*N*ACC_W-1:0]    acc_flat   // element (i*N+j)
);
    // Horizontal links: N rows x (N+1) positions
    wire [N*(N+1)*DW-1:0] a_link;
    wire [N*(N+1)-1:0]    va_link;
    // Vertical links: (N+1) positions x N columns
    wire [(N+1)*N*DW-1:0] b_link;
    wire [(N+1)*N-1:0]    vb_link;

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_left
            assign a_link [(i*(N+1))*DW +: DW] = a_left [i*DW +: DW];
            assign va_link[ i*(N+1)]           = va_left[i];
        end
        for (j = 0; j < N; j = j + 1) begin : g_top
            assign b_link [j*DW +: DW] = b_top [j*DW +: DW];
            assign vb_link[j]          = vb_top[j];
        end

        for (i = 0; i < N; i = i + 1) begin : row
            for (j = 0; j < N; j = j + 1) begin : col
                processing_element #(.DW(DW), .ACC_W(ACC_W)) pe (
                    .clk   (clk),
                    .rst   (rst),
                    .clr   (clr),
                    .en    (en),
                    .a_in  (a_link [(i*(N+1)+j  )*DW +: DW]),
                    .b_in  (b_link [( i   *N+j  )*DW +: DW]),
                    .va_in (va_link[ i*(N+1)+j  ]),
                    .vb_in (vb_link[ i   *N+j   ]),
                    .a_out (a_link [(i*(N+1)+j+1)*DW +: DW]),
                    .b_out (b_link [((i+1)*N+j  )*DW +: DW]),
                    .va_out(va_link[ i*(N+1)+j+1]),
                    .vb_out(vb_link[(i+1)*N+j   ]),
                    .prod  (),
                    .acc   (acc_flat[(i*N+j)*ACC_W +: ACC_W])
                );
            end
        end
    endgenerate
endmodule
