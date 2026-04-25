
`timescale 1 ns / 1 ps

// DDR Bandwidth Benchmark - AXI-Lite Register Controller
//
// Adapted from the repository's axi_lite_configs.v pattern.
// Provides 32 x 32-bit registers (7-bit address space) for configuration
// and status reporting of the 4-port DDR bandwidth benchmark engine.
//
// Register Map (word-addressed, byte offset shown):
//   0x00  CTRL          R/W  [0]=start (self-clearing), [1]=stop, [2]=sw_reset,
//                            [5:4]=mode (00=READ, 01=WRITE, 10=RD_WR_SPLIT)
//   0x04  STATUS        R    [3:0]=port_done[3:0], [7:4]=port_active[3:0],
//                            [8]=all_done, [9]=any_error
//   0x08  BURST_LEN     R/W  [7:0]=beats per burst (1-255, default 16)
//   0x0C  TOTAL_BURSTS  R/W  [15:0]=total bursts per port (default 256)
//   0x10  P0_BASE_LOW   R/W  Port 0 base address [31:0]
//   0x14  P0_BASE_HIGH  R/W  Port 0 base address [63:32]
//   0x18  P1_BASE_LOW   R/W  Port 1 base address [31:0]
//   0x1C  P1_BASE_HIGH  R/W  Port 1 base address [63:32]
//   0x20  P2_BASE_LOW   R/W  Port 2 base address [31:0]
//   0x24  P2_BASE_HIGH  R/W  Port 2 base address [63:32]
//   0x28  P3_BASE_LOW   R/W  Port 3 base address [31:0]
//   0x2C  P3_BASE_HIGH  R/W  Port 3 base address [63:32]
//   0x30  CYCLE_CNT_L   R    Elapsed cycles [31:0]  (captured at all_done)
//   0x34  CYCLE_CNT_H   R    Elapsed cycles [63:32]
//   0x38  P0_BEAT_CNT   R    Port 0 completed beat count
//   0x3C  P1_BEAT_CNT   R    Port 1 completed beat count
//   0x40  P2_BEAT_CNT   R    Port 2 completed beat count
//   0x44  P3_BEAT_CNT   R    Port 3 completed beat count
//   0x48  P0_BURST_CNT  R    Port 0 completed burst count
//   0x4C  P1_BURST_CNT  R    Port 1 completed burst count
//   0x50  P2_BURST_CNT  R    Port 2 completed burst count
//   0x54  P3_BURST_CNT  R    Port 3 completed burst count
//   0x58-0x7C  RESERVED

module ddr_bw_reg_ctrl #
(
    // Width of S_AXI data bus
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    // Width of S_AXI address bus (7 bits = 128 bytes = 32 registers)
    parameter integer C_S_AXI_ADDR_WIDTH = 7
)
(
    // --- Outputs to traffic generators ---
    output wire        start_pulse,      // one-cycle pulse: begin benchmark
    output wire        stop_req,         // request stop (graceful)
    output wire        sw_reset,         // synchronous reset to all engines
    output wire [1:0]  mode,             // 00=READ, 01=WRITE, 10=RD_WR_SPLIT
    output wire [7:0]  burst_len,        // beats per burst
    output wire [15:0] total_bursts,     // total bursts per port
    output wire [63:0] p0_base_addr,     // port 0 DDR base address
    output wire [63:0] p1_base_addr,     // port 1 DDR base address
    output wire [63:0] p2_base_addr,     // port 2 DDR base address
    output wire [63:0] p3_base_addr,     // port 3 DDR base address

    // --- Inputs from traffic generators / counter ---
    input  wire [3:0]  port_done,        // per-port done flags
    input  wire [3:0]  port_active,      // per-port active flags
    input  wire        all_done,         // all ports completed
    input  wire        any_error,        // any AXI error detected
    input  wire [63:0] cycle_count,      // elapsed cycles (from counter)
    input  wire [31:0] p0_beat_cnt,      // port 0 beat count
    input  wire [31:0] p1_beat_cnt,
    input  wire [31:0] p2_beat_cnt,
    input  wire [31:0] p3_beat_cnt,
    input  wire [31:0] p0_burst_cnt,     // port 0 burst count
    input  wire [31:0] p1_burst_cnt,
    input  wire [31:0] p2_burst_cnt,
    input  wire [31:0] p3_burst_cnt,

    // --- AXI4-Lite Slave Interface ---
    input  wire                             S_AXI_ACLK,
    input  wire                             S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [2:0]                       S_AXI_AWPROT,
    input  wire                             S_AXI_AWVALID,
    output wire                             S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                             S_AXI_WVALID,
    output wire                             S_AXI_WREADY,
    output wire [1:0]                       S_AXI_BRESP,
    output wire                             S_AXI_BVALID,
    input  wire                             S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [2:0]                       S_AXI_ARPROT,
    input  wire                             S_AXI_ARVALID,
    output wire                             S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_RDATA,
    output wire [1:0]                       S_AXI_RRESP,
    output wire                             S_AXI_RVALID,
    input  wire                             S_AXI_RREADY
);

    // AXI4-Lite internal signals (same pattern as axi_lite_configs.v)
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg  axi_awready;
    reg  axi_wready;
    reg [1:0] axi_bresp;
    reg  axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg  axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg [1:0] axi_rresp;
    reg  axi_rvalid;

    // ADDR_LSB = 2 for 32-bit data; OPT_MEM_ADDR_BITS = 4 → 5-bit index → 32 regs
    localparam integer ADDR_LSB          = (C_S_AXI_DATA_WIDTH/32) + 1; // = 2
    localparam integer OPT_MEM_ADDR_BITS = 4;  // 2^4 address bits above LSB = 32 regs

    // Slave registers
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg0;   // CTRL
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg2;   // BURST_LEN
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg3;   // TOTAL_BURSTS
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg4;   // P0_BASE_LOW
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg5;   // P0_BASE_HIGH
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg6;   // P1_BASE_LOW
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg7;   // P1_BASE_HIGH
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg8;   // P2_BASE_LOW
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg9;   // P2_BASE_HIGH
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg10;  // P3_BASE_LOW
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg11;  // P3_BASE_HIGH

    wire slv_reg_rden;
    wire slv_reg_wren;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;
    integer byte_index;
    reg  aw_en;

    // I/O connections
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    // ------------------------------------------------------------------
    // AXI4-Lite write address handshake (same as axi_lite_configs.v)
    // ------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awready <= 1'b0;
            aw_en       <= 1'b1;
        end else begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awready <= 1'b1;
                aw_en       <= 1'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                aw_en       <= 1'b1;
                axi_awready <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0)
            axi_awaddr <= 0;
        else if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
            axi_awaddr <= S_AXI_AWADDR;
    end

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0)
            axi_wready <= 1'b0;
        else if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en)
            axi_wready <= 1'b1;
        else
            axi_wready <= 1'b0;
    end

    assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

    // ------------------------------------------------------------------
    // Register write logic
    // ------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            slv_reg0  <= 32'h0;
            slv_reg2  <= 32'h10;    // default burst_len = 16
            slv_reg3  <= 32'h100;   // default total_bursts = 256
            slv_reg4  <= 32'h0;
            slv_reg5  <= 32'h0;
            slv_reg6  <= 32'h0;
            slv_reg7  <= 32'h0;
            slv_reg8  <= 32'h0;
            slv_reg9  <= 32'h0;
            slv_reg10 <= 32'h0;
            slv_reg11 <= 32'h0;
        end else begin
            // self-clear start bit (bit[0] of CTRL) after one cycle
            if (slv_reg0[0])
                slv_reg0[0] <= 1'b0;

            if (slv_reg_wren) begin
                case (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
                    5'h00: begin  // CTRL
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg0[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    end
                    // reg1 (STATUS) is read-only, ignore writes
                    5'h02: begin  // BURST_LEN
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg2[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    end
                    5'h03: begin  // TOTAL_BURSTS
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg3[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    end
                    5'h04: begin  // P0_BASE_LOW
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg4[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    end
                    5'h05: begin  // P0_BASE_HIGH
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg5[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    end
                    5'h06: begin  // P1_BASE_LOW
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg6[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    end
                    5'h07: begin  // P1_BASE_HIGH
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg7[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    end
                    5'h08: begin  // P2_BASE_LOW
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg8[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    end
                    5'h09: begin  // P2_BASE_HIGH
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg9[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    end
                    5'h0A: begin  // P3_BASE_LOW
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg10[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    end
                    5'h0B: begin  // P3_BASE_HIGH
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg11[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    end
                    default: ;
                endcase
            end
        end
    end

    // Write response
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_bvalid <= 0;
            axi_bresp  <= 2'b0;
        end else begin
            if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // AXI4-Lite read address handshake
    // ------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 1'b0;
            axi_araddr  <= 32'b0;
        end else begin
            if (~axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_rvalid <= 0;
            axi_rresp  <= 0;
        end else begin
            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b0;
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;

    // ------------------------------------------------------------------
    // Register read mux (combinational)
    // ------------------------------------------------------------------
    always @(*) begin
        case (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
            5'h00: reg_data_out = slv_reg0;
            5'h01: reg_data_out = {22'b0, any_error, all_done, port_active, port_done};
            5'h02: reg_data_out = slv_reg2;
            5'h03: reg_data_out = slv_reg3;
            5'h04: reg_data_out = slv_reg4;
            5'h05: reg_data_out = slv_reg5;
            5'h06: reg_data_out = slv_reg6;
            5'h07: reg_data_out = slv_reg7;
            5'h08: reg_data_out = slv_reg8;
            5'h09: reg_data_out = slv_reg9;
            5'h0A: reg_data_out = slv_reg10;
            5'h0B: reg_data_out = slv_reg11;
            5'h0C: reg_data_out = cycle_count[31:0];
            5'h0D: reg_data_out = cycle_count[63:32];
            5'h0E: reg_data_out = p0_beat_cnt;
            5'h0F: reg_data_out = p1_beat_cnt;
            5'h10: reg_data_out = p2_beat_cnt;
            5'h11: reg_data_out = p3_beat_cnt;
            5'h12: reg_data_out = p0_burst_cnt;
            5'h13: reg_data_out = p1_burst_cnt;
            5'h14: reg_data_out = p2_burst_cnt;
            5'h15: reg_data_out = p3_burst_cnt;
            default: reg_data_out = 32'h0;
        endcase
    end

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0)
            axi_rdata <= 0;
        else if (slv_reg_rden)
            axi_rdata <= reg_data_out;
    end

    // ------------------------------------------------------------------
    // Output assignments
    // ------------------------------------------------------------------
    // start_pulse: one cycle when CTRL[0] is written as 1
    assign start_pulse  = slv_reg0[0];
    assign stop_req     = slv_reg0[1];
    assign sw_reset     = slv_reg0[2];
    assign mode         = slv_reg0[5:4];
    assign burst_len    = slv_reg2[7:0];
    assign total_bursts = slv_reg3[15:0];
    assign p0_base_addr = {slv_reg5, slv_reg4};
    assign p1_base_addr = {slv_reg7, slv_reg6};
    assign p2_base_addr = {slv_reg9, slv_reg8};
    assign p3_base_addr = {slv_reg11, slv_reg10};

endmodule
