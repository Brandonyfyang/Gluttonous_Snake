
`timescale 1 ns / 1 ps

// DDR Bandwidth Benchmark - Hardware Bandwidth Counter
//
// Counts clock cycles from the first start until all 4 ports are done.
// Latches per-port beat and burst counts at the completion point.
// Provides frozen counter values that remain stable until the next run.

module ddr_bw_counter
(
    input  wire        clk,
    input  wire        resetn,      // active-low reset
    input  wire        sw_reset,    // software reset (from register)
    input  wire        start_pulse, // one-cycle start pulse
    input  wire [3:0]  port_done,   // per-port done from traffic generators
    input  wire [3:0]  port_active, // per-port active from traffic generators

    // Live per-port beat/burst counts from traffic generators
    input  wire [31:0] p0_beat_live,
    input  wire [31:0] p1_beat_live,
    input  wire [31:0] p2_beat_live,
    input  wire [31:0] p3_beat_live,
    input  wire [31:0] p0_burst_live,
    input  wire [31:0] p1_burst_live,
    input  wire [31:0] p2_burst_live,
    input  wire [31:0] p3_burst_live,

    // Outputs to register block (frozen at completion)
    output reg [63:0]  cycle_count,     // elapsed cycles
    output reg [31:0]  p0_beat_cnt,
    output reg [31:0]  p1_beat_cnt,
    output reg [31:0]  p2_beat_cnt,
    output reg [31:0]  p3_beat_cnt,
    output reg [31:0]  p0_burst_cnt,
    output reg [31:0]  p1_burst_cnt,
    output reg [31:0]  p2_burst_cnt,
    output reg [31:0]  p3_burst_cnt,
    output reg         all_done        // all 4 ports have completed
);

    // Running cycle counter
    reg [63:0] cycle_cnt_run;

    // Detect rising edge of all_done condition
    wire all_ports_done = &port_done;   // all four port_done bits high
    reg  all_done_prev;

    always @(posedge clk) begin
        if (!resetn || sw_reset) begin
            cycle_cnt_run <= 64'b0;
            cycle_count   <= 64'b0;
            p0_beat_cnt   <= 32'b0;
            p1_beat_cnt   <= 32'b0;
            p2_beat_cnt   <= 32'b0;
            p3_beat_cnt   <= 32'b0;
            p0_burst_cnt  <= 32'b0;
            p1_burst_cnt  <= 32'b0;
            p2_burst_cnt  <= 32'b0;
            p3_burst_cnt  <= 32'b0;
            all_done      <= 1'b0;
            all_done_prev <= 1'b0;
        end else begin
            all_done_prev <= all_ports_done;

            if (start_pulse) begin
                // Clear counters and start timing on start
                cycle_cnt_run <= 64'b0;
                cycle_count   <= 64'b0;
                all_done      <= 1'b0;
                all_done_prev <= 1'b0;
            end else if (|port_active || |port_done) begin
                // Count while any port is active or finishing
                if (!all_done)
                    cycle_cnt_run <= cycle_cnt_run + 64'b1;
            end

            // Latch results at rising edge of all_ports_done
            if (all_ports_done && !all_done_prev) begin
                all_done    <= 1'b1;
                cycle_count <= cycle_cnt_run;
                p0_beat_cnt  <= p0_beat_live;
                p1_beat_cnt  <= p1_beat_live;
                p2_beat_cnt  <= p2_beat_live;
                p3_beat_cnt  <= p3_beat_live;
                p0_burst_cnt <= p0_burst_live;
                p1_burst_cnt <= p1_burst_live;
                p2_burst_cnt <= p2_burst_live;
                p3_burst_cnt <= p3_burst_live;
            end
        end
    end

endmodule
