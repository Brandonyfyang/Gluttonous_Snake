
`timescale 1 ns / 1 ps

// DDR Bandwidth Benchmark - AXI4 Full Master Traffic Generator
//
// Adapted from the repository's axi_full_master_r.v / axi_full_master_w.v patterns.
// Each instance generates configurable AXI4 burst read or write traffic to PS DDR.
//
// Parameters:
//   PORT_ID            : 0-3, used for identification only
//   C_M_AXI_ADDR_WIDTH : address width (64 for KV260 HP ports)
//   C_M_AXI_DATA_WIDTH : data bus width (64 for HP port default)
//   C_M_AXI_ID_WIDTH   : AXI ID width
//
// Mode input:
//   1'b0 = READ  : issues AXI4 read bursts
//   1'b1 = WRITE : issues AXI4 write bursts
//
// Operation:
//   1. Assert start_pulse for one cycle to begin.
//   2. Engine issues total_bursts bursts of burst_len beats each.
//   3. Asserts done when all bursts complete.
//   4. beat_cnt / burst_cnt updated every beat / burst.

module ddr_bw_traffic_gen #
(
    parameter integer PORT_ID            = 0,
    parameter integer C_M_AXI_ID_WIDTH   = 1,
    parameter integer C_M_AXI_ADDR_WIDTH = 64,
    parameter integer C_M_AXI_DATA_WIDTH = 64
)
(
    // Control interface
    input  wire                              clk,
    input  wire                              resetn,       // active-low reset
    input  wire                              start_pulse,  // one-cycle start
    input  wire                              stop_req,     // request early stop
    input  wire                              mode,         // 0=read, 1=write
    input  wire [C_M_AXI_ADDR_WIDTH-1:0]    base_addr,    // DDR base address
    input  wire [7:0]                        burst_len,    // beats per burst (value, not -1)
    input  wire [15:0]                       total_bursts, // total bursts to issue

    // Status outputs
    output reg                               done,         // high when all done
    output reg                               active,       // high while running
    output reg                               error,        // AXI error detected
    output reg  [31:0]                       beat_cnt,     // running beat count
    output reg  [31:0]                       burst_cnt,    // running burst count

    // AXI4 Full Master - Write Address Channel
    output wire [C_M_AXI_ID_WIDTH-1:0]      M_AXI_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]    M_AXI_AWADDR,
    output wire [7:0]                        M_AXI_AWLEN,
    output wire [2:0]                        M_AXI_AWSIZE,
    output wire [1:0]                        M_AXI_AWBURST,
    output wire                              M_AXI_AWLOCK,
    output wire [3:0]                        M_AXI_AWCACHE,
    output wire [2:0]                        M_AXI_AWPROT,
    output wire [3:0]                        M_AXI_AWQOS,
    output wire                              M_AXI_AWVALID,
    input  wire                              M_AXI_AWREADY,

    // AXI4 Full Master - Write Data Channel
    output wire [C_M_AXI_DATA_WIDTH-1:0]    M_AXI_WDATA,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0]  M_AXI_WSTRB,
    output wire                              M_AXI_WLAST,
    output wire                              M_AXI_WVALID,
    input  wire                              M_AXI_WREADY,

    // AXI4 Full Master - Write Response Channel
    input  wire [C_M_AXI_ID_WIDTH-1:0]      M_AXI_BID,
    input  wire [1:0]                        M_AXI_BRESP,
    input  wire                              M_AXI_BVALID,
    output wire                              M_AXI_BREADY,

    // AXI4 Full Master - Read Address Channel
    output wire [C_M_AXI_ID_WIDTH-1:0]      M_AXI_ARID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]    M_AXI_ARADDR,
    output wire [7:0]                        M_AXI_ARLEN,
    output wire [2:0]                        M_AXI_ARSIZE,
    output wire [1:0]                        M_AXI_ARBURST,
    output wire                              M_AXI_ARLOCK,
    output wire [3:0]                        M_AXI_ARCACHE,
    output wire [2:0]                        M_AXI_ARPROT,
    output wire [3:0]                        M_AXI_ARQOS,
    output wire                              M_AXI_ARVALID,
    input  wire                              M_AXI_ARREADY,

    // AXI4 Full Master - Read Data Channel
    input  wire [C_M_AXI_ID_WIDTH-1:0]      M_AXI_RID,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]    M_AXI_RDATA,
    input  wire [1:0]                        M_AXI_RRESP,
    input  wire                              M_AXI_RLAST,
    input  wire                              M_AXI_RVALID,
    output wire                              M_AXI_RREADY
);

    // -----------------------------------------------------------------------
    // Local parameters
    // -----------------------------------------------------------------------
    // Data bytes per beat
    localparam integer BYTES_PER_BEAT = C_M_AXI_DATA_WIDTH / 8;

    // clogb2 function (same as in axi_full_master_r.v)
    function integer clogb2 (input integer bit_depth);
        begin
            for (clogb2 = 0; bit_depth > 0; clogb2 = clogb2 + 1)
                bit_depth = bit_depth >> 1;
        end
    endfunction

    localparam integer AXI_SIZE = clogb2(BYTES_PER_BEAT - 1); // e.g. 3 for 64-bit

    // State machine
    localparam [2:0]
        ST_IDLE    = 3'd0,
        ST_AR      = 3'd1,   // issue read address
        ST_R       = 3'd2,   // receive read data
        ST_AW      = 3'd3,   // issue write address
        ST_W       = 3'd4,   // send write data
        ST_B       = 3'd5,   // wait write response
        ST_DONE    = 3'd6;

    reg [2:0] state;

    // Internal registers
    reg [C_M_AXI_ADDR_WIDTH-1:0] cur_addr;        // current burst address
    reg [7:0]                     beat_idx;        // beat index within burst
    reg [15:0]                    burst_idx;       // burst index
    reg [7:0]                     burst_len_reg;   // latched burst_len
    reg [15:0]                    total_bursts_reg;// latched total_bursts
    reg                           mode_reg;        // latched mode
    reg [C_M_AXI_ADDR_WIDTH-1:0] base_addr_reg;   // latched base address

    // AXI channel handshake registers
    reg  axi_arvalid;
    reg  axi_rready;
    reg  axi_awvalid;
    reg  axi_wvalid;
    reg  axi_wlast;
    reg  axi_bready;

    // Write data pattern (incrementing, for traffic generation)
    reg [C_M_AXI_DATA_WIDTH-1:0] wdata_pattern;

    // Burst size in bytes (burst_len * BYTES_PER_BEAT)
    wire [C_M_AXI_ADDR_WIDTH-1:0] burst_size_bytes;
    assign burst_size_bytes = {56'b0, burst_len_reg} * BYTES_PER_BEAT;

    // -----------------------------------------------------------------------
    // Fixed AXI channel assignments (non-configurable fields)
    // -----------------------------------------------------------------------
    // Read Address
    assign M_AXI_ARID    = {C_M_AXI_ID_WIDTH{1'b0}};
    assign M_AXI_ARADDR  = cur_addr;
    assign M_AXI_ARLEN   = burst_len_reg - 8'd1;   // AXI burst len = beats - 1
    assign M_AXI_ARSIZE  = AXI_SIZE[2:0];
    assign M_AXI_ARBURST = 2'b01;    // INCR
    assign M_AXI_ARLOCK  = 1'b0;
    assign M_AXI_ARCACHE = 4'b0010;  // Normal, non-cacheable, bufferable
    assign M_AXI_ARPROT  = 3'b000;
    assign M_AXI_ARQOS   = 4'b0000;
    assign M_AXI_ARVALID = axi_arvalid;
    assign M_AXI_RREADY  = axi_rready;

    // Write Address
    assign M_AXI_AWID    = {C_M_AXI_ID_WIDTH{1'b0}};
    assign M_AXI_AWADDR  = cur_addr;
    assign M_AXI_AWLEN   = burst_len_reg - 8'd1;
    assign M_AXI_AWSIZE  = AXI_SIZE[2:0];
    assign M_AXI_AWBURST = 2'b01;
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0010;
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_AWQOS   = 4'b0000;
    assign M_AXI_AWVALID = axi_awvalid;

    // Write Data
    assign M_AXI_WDATA  = wdata_pattern;
    assign M_AXI_WSTRB  = {(C_M_AXI_DATA_WIDTH/8){1'b1}};
    assign M_AXI_WLAST  = axi_wlast;
    assign M_AXI_WVALID = axi_wvalid;
    assign M_AXI_BREADY = axi_bready;

    // -----------------------------------------------------------------------
    // Main state machine
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            state            <= ST_IDLE;
            axi_arvalid      <= 1'b0;
            axi_rready       <= 1'b0;
            axi_awvalid      <= 1'b0;
            axi_wvalid       <= 1'b0;
            axi_wlast        <= 1'b0;
            axi_bready       <= 1'b0;
            done             <= 1'b0;
            active           <= 1'b0;
            error            <= 1'b0;
            beat_cnt         <= 32'b0;
            burst_cnt        <= 32'b0;
            cur_addr         <= {C_M_AXI_ADDR_WIDTH{1'b0}};
            beat_idx         <= 8'b0;
            burst_idx        <= 16'b0;
            wdata_pattern    <= {{(C_M_AXI_DATA_WIDTH-8){1'b0}}, 8'hA5};
            burst_len_reg    <= 8'd16;
            total_bursts_reg <= 16'd256;
            mode_reg         <= 1'b0;
            base_addr_reg    <= {C_M_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            case (state)

                // ----------------------------------------------------------
                ST_IDLE: begin
                    done    <= 1'b0;
                    active  <= 1'b0;
                    if (start_pulse) begin
                        // Latch configuration at start
                        burst_len_reg    <= (burst_len == 8'b0) ? 8'd16 : burst_len;
                        total_bursts_reg <= (total_bursts == 16'b0) ? 16'd256 : total_bursts;
                        mode_reg         <= mode;
                        base_addr_reg    <= base_addr;
                        cur_addr         <= base_addr;
                        beat_cnt         <= 32'b0;
                        burst_cnt        <= 32'b0;
                        beat_idx         <= 8'b0;
                        burst_idx        <= 16'b0;
                        error            <= 1'b0;
                        wdata_pattern    <= {{(C_M_AXI_DATA_WIDTH-8){1'b0}}, 8'hA5};
                        active           <= 1'b1;
                        if (mode == 1'b0)
                            state <= ST_AR;
                        else
                            state <= ST_AW;
                    end
                end

                // ----------------------------------------------------------
                // READ path
                // ----------------------------------------------------------
                ST_AR: begin
                    if (stop_req) begin
                        state  <= ST_DONE;
                        active <= 1'b0;
                    end else begin
                        axi_arvalid <= 1'b1;
                        if (axi_arvalid && M_AXI_ARREADY) begin
                            axi_arvalid <= 1'b0;
                            axi_rready  <= 1'b1;
                            beat_idx    <= 8'b0;
                            state       <= ST_R;
                        end
                    end
                end

                ST_R: begin
                    if (M_AXI_RVALID && axi_rready) begin
                        beat_cnt <= beat_cnt + 32'b1;
                        beat_idx <= beat_idx + 8'b1;
                        if (M_AXI_RRESP != 2'b00)
                            error <= 1'b1;
                        if (M_AXI_RLAST) begin
                            axi_rready <= 1'b0;
                            burst_cnt  <= burst_cnt + 32'b1;
                            burst_idx  <= burst_idx + 16'b1;
                            cur_addr   <= cur_addr + burst_size_bytes;
                            if (burst_idx + 16'b1 >= total_bursts_reg) begin
                                state  <= ST_DONE;
                                active <= 1'b0;
                            end else begin
                                state <= ST_AR;
                            end
                        end
                    end
                end

                // ----------------------------------------------------------
                // WRITE path
                // ----------------------------------------------------------
                ST_AW: begin
                    if (stop_req) begin
                        state  <= ST_DONE;
                        active <= 1'b0;
                    end else begin
                        axi_awvalid <= 1'b1;
                        if (axi_awvalid && M_AXI_AWREADY) begin
                            axi_awvalid <= 1'b0;
                            axi_wvalid  <= 1'b1;
                            beat_idx    <= 8'b0;
                            axi_wlast   <= (burst_len_reg == 8'd1) ? 1'b1 : 1'b0;
                            state       <= ST_W;
                        end
                    end
                end

                ST_W: begin
                    if (axi_wvalid && M_AXI_WREADY) begin
                        beat_cnt      <= beat_cnt + 32'b1;
                        beat_idx      <= beat_idx + 8'b1;
                        wdata_pattern <= wdata_pattern + 1'b1;
                        if (axi_wlast) begin
                            axi_wvalid <= 1'b0;
                            axi_wlast  <= 1'b0;
                            axi_bready <= 1'b1;
                            state      <= ST_B;
                        end else if (beat_idx + 8'd2 >= burst_len_reg) begin
                            // next beat is the last
                            axi_wlast <= 1'b1;
                        end
                    end
                end

                ST_B: begin
                    if (M_AXI_BVALID && axi_bready) begin
                        axi_bready <= 1'b0;
                        if (M_AXI_BRESP != 2'b00)
                            error <= 1'b1;
                        burst_cnt <= burst_cnt + 32'b1;
                        burst_idx <= burst_idx + 16'b1;
                        cur_addr  <= cur_addr + burst_size_bytes;
                        if (burst_idx + 16'b1 >= total_bursts_reg) begin
                            state  <= ST_DONE;
                            active <= 1'b0;
                        end else begin
                            axi_awvalid <= 1'b1;
                            state       <= ST_AW;
                        end
                    end
                end

                // ----------------------------------------------------------
                ST_DONE: begin
                    done   <= 1'b1;
                    active <= 1'b0;
                    // Stay done until next start_pulse
                    if (start_pulse)
                        state <= ST_IDLE;
                end

                default: state <= ST_IDLE;

            endcase
        end
    end

endmodule
