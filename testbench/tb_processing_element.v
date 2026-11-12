// ============================================================================
// tb_processing_element.v - self-checking unit test for one PE.
// Each cycle the testbench updates its own reference model of the
// accumulator and of the forwarding registers and compares all outputs.
// ============================================================================
`timescale 1ns/1ps
module tb_processing_element;
    localparam DW = 16, ACC_W = 34;

    reg clk = 0, rst = 1, clr = 0, en = 0;
    reg  signed [DW-1:0] a_in = 0, b_in = 0;
    reg  va_in = 0, vb_in = 0;
    wire signed [DW-1:0] a_out, b_out;
    wire va_out, vb_out;
    wire signed [2*DW-1:0] prod;
    wire signed [ACC_W-1:0] acc;

    processing_element #(.DW(DW), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst(rst), .clr(clr), .en(en),
        .a_in(a_in), .b_in(b_in), .va_in(va_in), .vb_in(vb_in),
        .a_out(a_out), .b_out(b_out), .va_out(va_out), .vb_out(vb_out),
        .prod(prod), .acc(acc));

    always #5 clk = ~clk;

    // reference model
    reg signed [63:0] ref_acc;
    reg signed [DW-1:0] ref_a, ref_b;
    reg ref_va, ref_vb;
    reg signed [63:0] pend;      // product waiting in the MAC pipeline register
    reg pend_v;
    integer checks = 0, errors = 0;

    task apply(input signed [DW-1:0] a, input signed [DW-1:0] b,
               input va, input vb, input e, input c, input [255:0] what);
    begin
        @(negedge clk);
        a_in = a; b_in = b; va_in = va; vb_in = vb; en = e; clr = c;
        // combinational product check
        #1;
        checks = checks + 1;
        if (prod !== a*b) begin
            errors = errors + 1;
            $display("FAIL prod: %0d*%0d got %0d", a, b, prod);
        end
        // reference update (what the PE should do at the next edge)
        if (c) begin
            ref_acc = 0; ref_a = 0; ref_b = 0; ref_va = 0; ref_vb = 0;
            pend = 0; pend_v = 0;
        end else begin
            // stage 2 uses the product captured on the previous edge
            if (pend_v) ref_acc = ref_acc + pend;
            pend   = a*b;
            pend_v = e && va && vb;
            if (e) begin
                ref_a = a; ref_b = b; ref_va = va; ref_vb = vb;
            end
        end
        @(posedge clk); #1;
        checks = checks + 1;
        if (acc !== ref_acc[ACC_W-1:0] || a_out !== ref_a || b_out !== ref_b ||
            va_out !== ref_va || vb_out !== ref_vb) begin
            errors = errors + 1;
            $display("FAIL [%0s] acc=%0d exp=%0d a_out=%0d exp=%0d b_out=%0d exp=%0d v=%b%b exp=%b%b",
                     what, acc, ref_acc, a_out, ref_a, b_out, ref_b, va_out, vb_out, ref_va, ref_vb);
        end else
            $display("ok   [%0s] a=%6d b=%6d -> acc=%0d", what, a, b, acc);
    end
    endtask

    integer n;
    initial begin
        $dumpfile("simulation/waveforms/tb_processing_element.vcd");
        $dumpvars(0, tb_processing_element);
        ref_acc = 0; ref_a = 0; ref_b = 0; ref_va = 0; ref_vb = 0; pend = 0; pend_v = 0;
        repeat (2) @(posedge clk);
        @(negedge clk) rst = 0;

        $display("--- basic MAC (Q8.8: 1.0 = 256) ---");
        apply( 256,  512, 1, 1, 1, 0, "1.0*2.0");
        apply( 768, -256, 1, 1, 1, 0, "3.0*-1.0");
        apply(-384, -128, 1, 1, 1, 0, "-1.5*-0.5");
        apply(  64,  1024, 1, 1, 1, 0, "0.25*4.0");

        $display("--- valid gating ---");
        apply( 999,  999, 0, 1, 1, 0, "va=0 no MAC");
        apply( 999,  999, 1, 0, 1, 0, "vb=0 no MAC");

        $display("--- enable / stall ---");
        apply( 512,  512, 1, 1, 0, 0, "en=0 hold");
        apply( 512,  512, 1, 1, 1, 0, "en=1 resume");

        apply(   0,    0, 0, 0, 1, 0, "flush pipeline");
        $display("--- extremes ---");
        apply(-32768, -32768, 1, 1, 1, 0, "min*min");
        apply( 32767, -32768, 1, 1, 1, 0, "max*min");
        apply( 32767,  32767, 1, 1, 1, 0, "max*max");

        apply(   0,    0, 0, 0, 1, 0, "flush pipeline");
        $display("--- clear ---");
        apply(   0,    0, 0, 0, 1, 1, "clr");

        $display("--- 40 random cycles ---");
        for (n = 0; n < 40; n = n + 1)
            apply($random, $random, $random, $random, ($random % 4) != 0, 0, "random");

        $display("--- synchronous reset ---");
        @(negedge clk) rst = 1; @(posedge clk); #1;
        checks = checks + 1;
        if (acc !== 0 || va_out !== 0 || vb_out !== 0) begin
            errors = errors + 1; $display("FAIL reset");
        end else $display("ok   [reset] acc=0");

        $display("==============================================");
        $display("PE TESTBENCH: %0d checks, %0d errors -> %s",
                 checks, errors, (errors == 0) ? "PASS" : "FAIL");
        $display("==============================================");
        $finish;
    end
endmodule
