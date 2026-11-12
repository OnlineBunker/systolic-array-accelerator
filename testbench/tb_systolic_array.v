// ============================================================================
// tb_systolic_array.v - tests the bare 4x4 array. The testbench produces the
// diagonal skew itself, so this checks the PE interconnect independently of
// the input buffers and controller.
// ============================================================================
`timescale 1ns/1ps
module tb_systolic_array;
    localparam N = 4, DW = 16, ACC_W = 34;

    reg clk = 0, rst = 1, clr = 0, en = 0;
    reg  [N*DW-1:0] a_left = 0, b_top = 0;
    reg  [N-1:0]    va_left = 0, vb_top = 0;
    wire [N*N*ACC_W-1:0] acc_flat;

    systolic_array #(.N(N), .DW(DW), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst(rst), .clr(clr), .en(en),
        .a_left(a_left), .va_left(va_left), .b_top(b_top), .vb_top(vb_top),
        .acc_flat(acc_flat));

    always #5 clk = ~clk;

    reg signed [DW-1:0] A [0:N*N-1];
    reg signed [DW-1:0] B [0:N*N-1];
    reg signed [63:0]   R [0:N*N-1];
    integer total_pass = 0, total_fail = 0;
    integer i, j, k, s, cyc;

    task compute_ref;
    begin
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                R[i*N+j] = 0;
                for (k = 0; k < N; k = k + 1)
                    R[i*N+j] = R[i*N+j] + A[i*N+k] * B[k*N+j];
            end
    end
    endtask

    task run(input [255:0] name);
        reg signed [ACC_W-1:0] got;
        integer bad;
    begin
        compute_ref;
        @(negedge clk) clr = 1; en = 0;
        @(negedge clk) clr = 0; en = 1;
        // 2N-1 skewed feed steps + (N-1) hops + 1 MAC pipeline stage to drain
        for (s = 0; s < 3*N - 1; s = s + 1) begin
            for (i = 0; i < N; i = i + 1) begin
                k = s - i;
                if (k >= 0 && k < N) begin
                    a_left[i*DW +: DW] = A[i*N + k]; va_left[i] = 1;
                    b_top [i*DW +: DW] = B[k*N + i]; vb_top[i]  = 1;
                end else begin
                    a_left[i*DW +: DW] = 0; va_left[i] = 0;
                    b_top [i*DW +: DW] = 0; vb_top[i]  = 0;
                end
            end
            @(negedge clk);
        end
        en = 0;
        bad = 0;
        for (i = 0; i < N*N; i = i + 1) begin
            got = acc_flat[i*ACC_W +: ACC_W];
            if (got !== R[i][ACC_W-1:0]) begin
                bad = bad + 1;
                $display("  FAIL C[%0d][%0d] got %0d exp %0d", i/N, i%N, got, R[i]);
            end
        end
        if (bad == 0) begin total_pass = total_pass + 1; $display("PASS  %0s", name); end
        else          begin total_fail = total_fail + 1; $display("FAIL  %0s (%0d/16 wrong)", name, bad); end
    end
    endtask

    integer t;
    initial begin
        $dumpfile("simulation/waveforms/tb_systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);
        repeat (2) @(posedge clk);
        @(negedge clk) rst = 0;

        // Identity
        for (i = 0; i < 16; i = i + 1) begin
            A[i] = (i + 1) * 256; B[i] = (i/4 == i%4) ? 256 : 0;
        end
        run("identity");

        // All-ones times all-twos
        for (i = 0; i < 16; i = i + 1) begin A[i] = 256; B[i] = 512; end
        run("ones x twos");

        // Signed extremes
        for (i = 0; i < 16; i = i + 1) begin A[i] = -32768; B[i] = -32768; end
        run("min x min (largest positive sum)");
        for (i = 0; i < 16; i = i + 1) begin A[i] = -32768; B[i] = 32767; end
        run("min x max (largest negative sum)");

        // Random
        for (t = 0; t < 50; t = t + 1) begin
            for (i = 0; i < 16; i = i + 1) begin A[i] = $random; B[i] = $random; end
            run("random");
        end

        $display("==============================================");
        $display("ARRAY TESTBENCH: %0d passed, %0d failed -> %s",
                 total_pass, total_fail, (total_fail == 0) ? "PASS" : "FAIL");
        $display("==============================================");
        $finish;
    end
endmodule
