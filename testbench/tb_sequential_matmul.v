// ============================================================================
// tb_sequential_matmul.v - verifies the single-MAC baseline and measures its
// start-to-done latency, for comparison with the systolic array.
// ============================================================================
`timescale 1ns/1ps
module tb_sequential_matmul;
    reg clk = 0, rst = 1, start = 0, wr_en = 0, wr_sel = 0;
    reg [3:0] wr_addr = 0, rd_addr = 0;
    reg [15:0] wr_data = 0;
    wire signed [33:0] rd_raw;
    wire busy, done;

    sequential_matmul dut (.clk(clk), .rst(rst), .start(start), .wr_en(wr_en),
        .wr_sel(wr_sel), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_addr(rd_addr), .rd_raw(rd_raw), .busy(busy), .done(done));

    always #5 clk = ~clk;

    reg signed [15:0] A [0:15];
    reg signed [15:0] B [0:15];
    reg signed [63:0] R;
    integer i, j, k, t, bad, latency, fails = 0;

    initial begin
        $dumpfile("simulation/waveforms/tb_sequential_matmul.vcd");
        $dumpvars(0, tb_sequential_matmul);
        repeat (3) @(posedge clk);
        @(negedge clk) rst = 0;
        for (t = 0; t < 20; t = t + 1) begin
            for (i = 0; i < 16; i = i + 1) begin
                A[i] = (t == 0) ? (i+1)*256 : $random;
                B[i] = (t == 0) ? ((i/4 == i%4) ? 256 : 0) : $random;
                @(negedge clk) wr_en = 1; wr_sel = 0; wr_addr = i; wr_data = A[i];
                @(negedge clk) wr_en = 1; wr_sel = 1; wr_addr = i; wr_data = B[i];
            end
            @(negedge clk) wr_en = 0; start = 1;
            @(posedge clk); latency = 0;
            @(negedge clk) start = 0;
            while (!done) begin @(posedge clk); latency = latency + 1; #1; end
            bad = 0;
            for (i = 0; i < 4; i = i + 1)
                for (j = 0; j < 4; j = j + 1) begin
                    R = 0;
                    for (k = 0; k < 4; k = k + 1) R = R + A[i*4+k] * B[k*4+j];
                    rd_addr = i*4 + j; #1;
                    if (rd_raw !== R[33:0]) bad = bad + 1;
                end
            if (bad) fails = fails + 1;
        end
        // sustained throughput: hold start high, measure period between done pulses
        begin : thr
            integer c, e1, e2, jobs;
            c = 0; jobs = 0;
            @(negedge clk) start = 1;
            while (jobs < 6) begin
                @(posedge clk); c = c + 1; #1;
                if (done && !busy) begin
                    jobs = jobs + 1;
                    if (jobs == 2) e1 = c;
                    if (jobs == 6) e2 = c;
                    @(posedge clk); c = c + 1; #1;   // done is a level; skip the restart edge
                end
            end
            @(negedge clk) start = 0;
            $display("Sustained throughput (start held high): %0d cycles per 4x4 product", (e2 - e1) / 4);
        end
        $display("==============================================");
        $display("SEQUENTIAL BASELINE: 20 cases, %0d failed -> %s", fails, fails ? "FAIL" : "PASS");
        $display("Measured latency start->done: %0d cycles", latency);
        $display("==============================================");
        $finish;
    end
endmodule
