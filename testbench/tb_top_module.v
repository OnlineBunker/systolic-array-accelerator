// ============================================================================
// tb_top_module.v - end-to-end test of the complete accelerator.
// Loads A and B through the host port, pulses start, waits for done,
// reads all 16 results and compares them against a reference model
// computed independently in the testbench (64-bit integer arithmetic).
// Both the full-precision result and the rounded/saturated Q8.8 result
// are checked. Start-to-done latency is measured in clock cycles.
// ============================================================================
`timescale 1ns/1ps
module tb_top_module;
    localparam N = 4, DW = 16, ACC_W = 34, FRAC = 8;

    reg clk = 0, rst = 1, start = 0;
    reg wr_en = 0, wr_sel = 0;
    reg [3:0]  wr_addr = 0, rd_addr = 0;
    reg [15:0] wr_data = 0;
    wire signed [ACC_W-1:0] rd_raw;
    wire signed [DW-1:0]    rd_q88;
    wire rd_ovf, busy, done;

    top_module dut (
        .clk(clk), .rst(rst), .start(start),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_addr(rd_addr), .rd_raw(rd_raw), .rd_q88(rd_q88), .rd_ovf(rd_ovf),
        .busy(busy), .done(done));

    always #5 clk = ~clk;   // 100 MHz simulation clock

    reg signed [DW-1:0] A [0:15];
    reg signed [DW-1:0] B [0:15];
    reg signed [63:0]   R [0:15];
    integer i, j, k, cases_pass = 0, cases_fail = 0, latency;

    // -------------------------------------------------------------- helpers
    function signed [DW-1:0] q;            // integer -> Q8.8
        input integer v; q = v * 256;
    endfunction

    function signed [63:0] ref_q88;        // round-to-nearest + saturate
        input signed [63:0] raw;
        reg signed [63:0] r;
    begin
        r = (raw + 128) >>> FRAC;
        if (r >  32767) r =  32767;
        if (r < -32768) r = -32768;
        ref_q88 = r;
    end
    endfunction

    task load_all;
    begin
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk); wr_en = 1; wr_sel = 0; wr_addr = i; wr_data = A[i];
            @(negedge clk); wr_en = 1; wr_sel = 1; wr_addr = i; wr_data = B[i];
        end
        @(negedge clk); wr_en = 0;
    end
    endtask

    task compute_ref;
    begin
        for (i = 0; i < 4; i = i + 1)
            for (j = 0; j < 4; j = j + 1) begin
                R[i*4+j] = 0;
                for (k = 0; k < 4; k = k + 1)
                    R[i*4+j] = R[i*4+j] + A[i*4+k] * B[k*4+j];
            end
    end
    endtask

    task start_and_wait;
    begin
        @(negedge clk) start = 1;
        @(posedge clk); latency = 0;     // start sampled on this edge
        @(negedge clk) start = 0;
        while (!done) begin @(posedge clk); latency = latency + 1; #1; end
    end
    endtask

    task print_mat(input integer which);   // 0 = A, 1 = B
    begin
        for (i = 0; i < 4; i = i + 1)
            if (which == 0)
                $display("    %8.3f %8.3f %8.3f %8.3f", A[i*4]/256.0, A[i*4+1]/256.0, A[i*4+2]/256.0, A[i*4+3]/256.0);
            else
                $display("    %8.3f %8.3f %8.3f %8.3f", B[i*4]/256.0, B[i*4+1]/256.0, B[i*4+2]/256.0, B[i*4+3]/256.0);
    end
    endtask

    task check(input [511:0] name, input verbose);
        integer bad;
        reg signed [63:0] eq;
        reg [8*64-1:0] line;
    begin
        compute_ref;
        bad = 0;
        if (verbose) begin
            $display("");
            $display("=== %0s ===", name);
            $display("  A ="); print_mat(0);
            $display("  B ="); print_mat(1);
            $display("  C = A x B (hardware, Q8.8)       | expected");
        end
        for (i = 0; i < 16; i = i + 1) begin
            rd_addr = i; #1;
            eq = ref_q88(R[i]);
            if (rd_raw !== R[i][ACC_W-1:0] || rd_q88 !== eq[15:0] ||
                rd_ovf !== (R[i] + 128 >>> 8 > 32767 || R[i] + 128 >>> 8 < -32768)) begin
                bad = bad + 1;
                $display("  MISMATCH C[%0d][%0d]: raw %0d (exp %0d) q88 %0d (exp %0d) ovf %b",
                         i/4, i%4, rd_raw, R[i], rd_q88, eq, rd_ovf);
            end
        end
        if (verbose) begin
            for (i = 0; i < 4; i = i + 1) begin
                rd_addr = i*4;   #1; $write("    %8.3f", rd_raw/65536.0);
                rd_addr = i*4+1; #1; $write(" %8.3f", rd_raw/65536.0);
                rd_addr = i*4+2; #1; $write(" %8.3f", rd_raw/65536.0);
                rd_addr = i*4+3; #1; $write(" %8.3f", rd_raw/65536.0);
                $display("  | %8.3f %8.3f %8.3f %8.3f",
                         R[i*4]/65536.0, R[i*4+1]/65536.0, R[i*4+2]/65536.0, R[i*4+3]/65536.0);
            end
            $display("  latency (start -> done): %0d clock cycles", latency);
        end
        if (bad == 0) begin
            cases_pass = cases_pass + 1;
            $display("  [PASS] %0s : 16/16 elements match", name);
        end else begin
            cases_fail = cases_fail + 1;
            $display("  [FAIL] %0s : %0d/16 elements wrong", name, bad);
        end
    end
    endtask

    integer t, saw_ovf;
    reg signed [DW-1:0] saveB [0:15];
    initial begin
        $dumpfile("simulation/waveforms/tb_top_module.vcd");
        $dumpvars(0, tb_top_module);
        repeat (3) @(posedge clk);
        @(negedge clk) rst = 0;

        // ---------------------------------------------------- TEST CASE 1
        A[ 0]=q(1); A[ 1]=q(2); A[ 2]=q(3); A[ 3]=q(4);
        A[ 4]=q(5); A[ 5]=q(6); A[ 6]=q(7); A[ 7]=q(8);
        A[ 8]=q(9); A[ 9]=q(1); A[10]=q(2); A[11]=q(3);
        A[12]=q(4); A[13]=q(5); A[14]=q(6); A[15]=q(7);
        for (i = 0; i < 16; i = i + 1) B[i] = (i/4 == i%4) ? q(1) : q(0);
        load_all; start_and_wait;
        check("TEST CASE 1: A x I = A", 1);
        // explicit identity property check: C must equal A exactly
        for (i = 0; i < 16; i = i + 1) begin
            rd_addr = i; #1;
            if (rd_q88 !== A[i]) $display("  identity property violated at %0d", i);
        end

        // ---------------------------------------------------- TEST CASE 2
        B[ 0]=q(1); B[ 1]=q(2); B[ 2]=q(0); B[ 3]=q(1);
        B[ 4]=q(0); B[ 5]=q(1); B[ 6]=q(2); B[ 7]=q(0);
        B[ 8]=q(1); B[ 9]=q(0); B[10]=q(1); B[11]=q(2);
        B[12]=q(2); B[13]=q(1); B[14]=q(0); B[15]=q(1);
        load_all; start_and_wait;
        check("TEST CASE 2: general integer matrices", 1);

        // ---------------------------------------------------- TEST CASE 3
        // negative and fractional Q8.8 operands
        A[ 0]= -384; A[ 1]=  64;  A[ 2]=  640; A[ 3]= -32;   // -1.5   0.25   2.5  -0.125
        A[ 4]=  800; A[ 5]=-512;  A[ 6]=  -96; A[ 7]= 128;   //  3.125 -2.0  -0.375 0.5
        A[ 8]= -256; A[ 9]=-256;  A[10]= -256; A[11]=-256;   //  -1    -1    -1    -1
        A[12]= 1  ;  A[13]=-1;    A[14]= 2000; A[15]=-1792;  //  1/256 -1/256 7.8125 -7.0
        B[ 0]=  192; B[ 1]=-128;  B[ 2]=  256; B[ 3]=  0;    //  0.75  -0.5   1     0
        B[ 4]= -704; B[ 5]= 1152; B[ 6]=  -64; B[ 7]= 256;   // -2.75   4.5  -0.25  1
        B[ 8]=   32; B[ 9]=  -32; B[10]=-1280; B[11]= 384;   //  0.125 -0.125 -5    1.5
        B[12]= -256; B[13]= 2304; B[14]=   80; B[15]=-640;   // -1      9    0.3125 -2.5
        load_all; start_and_wait;
        check("TEST CASE 3: negative and fractional values", 1);

        // ---------------------------------------------------- TEST CASE 4
        // signed extremes: every product is (-128.0)^2; accumulator must not
        // overflow, Q8.8 view must saturate and flag overflow
        for (i = 0; i < 16; i = i + 1) begin A[i] = -32768; B[i] = -32768; end
        load_all; start_and_wait;
        check("TEST CASE 4: extreme values (-128.0 x -128.0)", 1);
        rd_addr = 0; #1;
        if (!rd_ovf) $display("  expected overflow flag on Q8.8 output was not set");
        else         $display("  overflow flag correctly set, Q8.8 saturated to %0d", rd_q88);

        // ---------------------------------------------------- TEST CASE 5
        for (i = 0; i < 16; i = i + 1) begin A[i] = 0; B[i] = $random; end
        load_all; start_and_wait;
        check("TEST CASE 5: zero matrix", 0);

        // ---------------------------------------------------- TEST CASE 6
        // back-to-back runs without reloading: the accumulators must be
        // cleared by the controller, not keep the previous result
        for (i = 0; i < 16; i = i + 1) begin A[i] = $random % 1024; B[i] = $random % 1024; end
        load_all; start_and_wait; start_and_wait;
        check("TEST CASE 6: back-to-back start (accumulator clear)", 0);

        // ---------------------------------------------------- TEST CASE 7
        // writes while busy must be ignored
        @(negedge clk) start = 1;
        @(negedge clk) start = 0;
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk); wr_en = 1; wr_sel = i[0]; wr_addr = i; wr_data = 16'h7FFF;
        end
        @(negedge clk) wr_en = 0;
        while (!done) @(posedge clk);
        #1; start_and_wait;   // run again with buffers that must be unchanged
        check("TEST CASE 7: writes ignored while busy", 0);

        // ---------------------------------------------------- RANDOM
        for (t = 0; t < 100; t = t + 1) begin
            for (i = 0; i < 16; i = i + 1) begin A[i] = $random; B[i] = $random; end
            load_all; start_and_wait;
            check("RANDOM full-range", 0);
        end

        // ---------------------------------------------------- THROUGHPUT
        // hold start high and measure the period between completions
        begin : thr
            integer c, e1, e2, jobs;
            c = 0; jobs = 0; e1 = 0; e2 = 0;
            @(negedge clk) start = 1;
            while (jobs < 6) begin
                @(posedge clk); c = c + 1; #1;
                if (done) begin
                    jobs = jobs + 1;
                    if (jobs == 2) e1 = c;
                    if (jobs == 6) e2 = c;
                end
            end
            @(negedge clk) start = 0;
            $display("");
            $display("Sustained throughput (start held high): %0d cycles per 4x4 product (measured over 4 jobs)",
                     (e2 - e1) / 4);
            check("THROUGHPUT run result still correct", 0);
        end

        $display("");
        $display("==============================================");
        $display("TOP TESTBENCH: %0d test cases passed, %0d failed -> %s",
                 cases_pass, cases_fail, (cases_fail == 0) ? "PASS" : "FAIL");
        $display("Measured latency start->done: %0d cycles", latency);
        $display("==============================================");
        $finish;
    end
endmodule
