// ============================================================================
// systolic_controller.v
// FSM:  IDLE -> CLEAR -> FEED (2N-1 cycles) -> DRAIN (N+1 cycles)
//            -> CAPTURE -> DONE (holds done=1 until next start)
//
//   FEED : step = 0 .. 2N-2 drives the skewed input buffers
//   DRAIN: 1 cycle of buffer latency + (N-1) hops for the last operands to
//          reach PE(N-1,N-1) + 1 cycle for the MAC's product register
// ============================================================================
`timescale 1ns/1ps
module systolic_controller #(
    parameter N  = 4,
    parameter SW = $clog2(2*N)
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          start,
    output reg           clr,
    output reg           array_en,
    output reg           feed_en,
    output reg  [SW-1:0] step,
    output reg           capture,
    output reg           busy,
    output reg           done
);
    localparam [2:0] S_IDLE    = 3'd0,
                     S_CLEAR   = 3'd1,
                     S_FEED    = 3'd2,
                     S_DRAIN   = 3'd3,
                     S_CAPTURE = 3'd4,
                     S_DONE    = 3'd5;

    localparam LAST_STEP   = 2*N - 2;
    localparam DRAIN_LAST  = N;      // N+1 drain cycles (incl. MAC pipeline stage)

    reg [2:0]    state;
    reg [SW-1:0] cnt;

    // ---------------- state register ----------------
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            cnt   <= {SW{1'b0}};
        end else begin
            case (state)
                S_IDLE:    if (start) state <= S_CLEAR;
                S_CLEAR:   begin state <= S_FEED; cnt <= {SW{1'b0}}; end
                S_FEED:    if (cnt == LAST_STEP[SW-1:0]) begin
                               state <= S_DRAIN; cnt <= {SW{1'b0}};
                           end else cnt <= cnt + 1'b1;
                S_DRAIN:   if (cnt == DRAIN_LAST[SW-1:0]) state <= S_CAPTURE;
                           else cnt <= cnt + 1'b1;
                S_CAPTURE: state <= S_DONE;
                S_DONE:    if (start) state <= S_CLEAR;
                default:   state <= S_IDLE;
            endcase
        end
    end

    // ---------------- outputs (Moore) ----------------
    always @(*) begin
        clr      = (state == S_CLEAR);
        feed_en  = (state == S_FEED);
        step     = (state == S_FEED) ? cnt : {SW{1'b0}};
        array_en = (state == S_FEED) || (state == S_DRAIN);
        capture  = (state == S_CAPTURE);
        busy     = (state != S_IDLE) && (state != S_DONE);
        done     = (state == S_DONE);
    end
endmodule
