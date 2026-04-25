
`timescale 1 ns / 1 ps

// DDR Bandwidth Benchmark - Top-Level Integration
//
// Instantiates:
//   - ddr_bw_reg_ctrl  : AXI4-Lite slave register block
//   - 4× ddr_bw_traffic_gen : AXI4 Full Master traffic generators (one per HP port)
//   - ddr_bw_counter       : Hardware cycle and bandwidth counter
//
// Port/mode mapping:
//   mode=00 (READ)        : all 4 ports issue read bursts
//   mode=01 (WRITE)       : all 4 ports issue write bursts
//   mode=10 (RD_WR_SPLIT) : ports 0,1 read; ports 2,3 write
//
// AXI4 Full Master data width: 64-bit (KV260 HP port compatible)
// AXI4 Full Master address width: 64-bit
//
// Integration notes for Vivado block design (KV260):
//   - Connect s_axi_ctrl to PS AXI-Lite master (GP0/GP1)
//   - Connect m_axi_port0..3 to PS HP slave ports (HP0..HP3)
//   - Set aclk from PS pl_clk0 (nominal 300 MHz on KV260)
//   - Set aresetn from Processor System Reset peripheral

module ddr_bw_top #
(
    parameter integer C_S_AXI_CTRL_ADDR_WIDTH = 7,
    parameter integer C_S_AXI_CTRL_DATA_WIDTH = 32,
    parameter integer C_M_AXI_ADDR_WIDTH      = 64,
    parameter integer C_M_AXI_DATA_WIDTH      = 64,
    parameter integer C_M_AXI_ID_WIDTH        = 1
)
(
    // Global clock and reset
    input  wire        aclk,
    input  wire        aresetn,

    // -----------------------------------------------------------------------
    // AXI4-Lite Control Slave (connect to PS GP port)
    // -----------------------------------------------------------------------
    input  wire [C_S_AXI_CTRL_ADDR_WIDTH-1:0] s_axi_ctrl_AWADDR,
    input  wire [2:0]                          s_axi_ctrl_AWPROT,
    input  wire                                s_axi_ctrl_AWVALID,
    output wire                                s_axi_ctrl_AWREADY,
    input  wire [C_S_AXI_CTRL_DATA_WIDTH-1:0] s_axi_ctrl_WDATA,
    input  wire [(C_S_AXI_CTRL_DATA_WIDTH/8)-1:0] s_axi_ctrl_WSTRB,
    input  wire                                s_axi_ctrl_WVALID,
    output wire                                s_axi_ctrl_WREADY,
    output wire [1:0]                          s_axi_ctrl_BRESP,
    output wire                                s_axi_ctrl_BVALID,
    input  wire                                s_axi_ctrl_BREADY,
    input  wire [C_S_AXI_CTRL_ADDR_WIDTH-1:0] s_axi_ctrl_ARADDR,
    input  wire [2:0]                          s_axi_ctrl_ARPROT,
    input  wire                                s_axi_ctrl_ARVALID,
    output wire                                s_axi_ctrl_ARREADY,
    output wire [C_S_AXI_CTRL_DATA_WIDTH-1:0] s_axi_ctrl_RDATA,
    output wire [1:0]                          s_axi_ctrl_RRESP,
    output wire                                s_axi_ctrl_RVALID,
    input  wire                                s_axi_ctrl_RREADY,

    // -----------------------------------------------------------------------
    // AXI4 Full Master Port 0 (connect to PS HP0)
    // -----------------------------------------------------------------------
    output wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port0_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]   m_axi_port0_AWADDR,
    output wire [7:0]                       m_axi_port0_AWLEN,
    output wire [2:0]                       m_axi_port0_AWSIZE,
    output wire [1:0]                       m_axi_port0_AWBURST,
    output wire                             m_axi_port0_AWLOCK,
    output wire [3:0]                       m_axi_port0_AWCACHE,
    output wire [2:0]                       m_axi_port0_AWPROT,
    output wire [3:0]                       m_axi_port0_AWQOS,
    output wire                             m_axi_port0_AWVALID,
    input  wire                             m_axi_port0_AWREADY,
    output wire [C_M_AXI_DATA_WIDTH-1:0]   m_axi_port0_WDATA,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_port0_WSTRB,
    output wire                             m_axi_port0_WLAST,
    output wire                             m_axi_port0_WVALID,
    input  wire                             m_axi_port0_WREADY,
    input  wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port0_BID,
    input  wire [1:0]                       m_axi_port0_BRESP,
    input  wire                             m_axi_port0_BVALID,
    output wire                             m_axi_port0_BREADY,
    output wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port0_ARID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]   m_axi_port0_ARADDR,
    output wire [7:0]                       m_axi_port0_ARLEN,
    output wire [2:0]                       m_axi_port0_ARSIZE,
    output wire [1:0]                       m_axi_port0_ARBURST,
    output wire                             m_axi_port0_ARLOCK,
    output wire [3:0]                       m_axi_port0_ARCACHE,
    output wire [2:0]                       m_axi_port0_ARPROT,
    output wire [3:0]                       m_axi_port0_ARQOS,
    output wire                             m_axi_port0_ARVALID,
    input  wire                             m_axi_port0_ARREADY,
    input  wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port0_RID,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]   m_axi_port0_RDATA,
    input  wire [1:0]                       m_axi_port0_RRESP,
    input  wire                             m_axi_port0_RLAST,
    input  wire                             m_axi_port0_RVALID,
    output wire                             m_axi_port0_RREADY,

    // -----------------------------------------------------------------------
    // AXI4 Full Master Port 1 (connect to PS HP1)
    // -----------------------------------------------------------------------
    output wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port1_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]   m_axi_port1_AWADDR,
    output wire [7:0]                       m_axi_port1_AWLEN,
    output wire [2:0]                       m_axi_port1_AWSIZE,
    output wire [1:0]                       m_axi_port1_AWBURST,
    output wire                             m_axi_port1_AWLOCK,
    output wire [3:0]                       m_axi_port1_AWCACHE,
    output wire [2:0]                       m_axi_port1_AWPROT,
    output wire [3:0]                       m_axi_port1_AWQOS,
    output wire                             m_axi_port1_AWVALID,
    input  wire                             m_axi_port1_AWREADY,
    output wire [C_M_AXI_DATA_WIDTH-1:0]   m_axi_port1_WDATA,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_port1_WSTRB,
    output wire                             m_axi_port1_WLAST,
    output wire                             m_axi_port1_WVALID,
    input  wire                             m_axi_port1_WREADY,
    input  wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port1_BID,
    input  wire [1:0]                       m_axi_port1_BRESP,
    input  wire                             m_axi_port1_BVALID,
    output wire                             m_axi_port1_BREADY,
    output wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port1_ARID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]   m_axi_port1_ARADDR,
    output wire [7:0]                       m_axi_port1_ARLEN,
    output wire [2:0]                       m_axi_port1_ARSIZE,
    output wire [1:0]                       m_axi_port1_ARBURST,
    output wire                             m_axi_port1_ARLOCK,
    output wire [3:0]                       m_axi_port1_ARCACHE,
    output wire [2:0]                       m_axi_port1_ARPROT,
    output wire [3:0]                       m_axi_port1_ARQOS,
    output wire                             m_axi_port1_ARVALID,
    input  wire                             m_axi_port1_ARREADY,
    input  wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port1_RID,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]   m_axi_port1_RDATA,
    input  wire [1:0]                       m_axi_port1_RRESP,
    input  wire                             m_axi_port1_RLAST,
    input  wire                             m_axi_port1_RVALID,
    output wire                             m_axi_port1_RREADY,

    // -----------------------------------------------------------------------
    // AXI4 Full Master Port 2 (connect to PS HP2)
    // -----------------------------------------------------------------------
    output wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port2_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]   m_axi_port2_AWADDR,
    output wire [7:0]                       m_axi_port2_AWLEN,
    output wire [2:0]                       m_axi_port2_AWSIZE,
    output wire [1:0]                       m_axi_port2_AWBURST,
    output wire                             m_axi_port2_AWLOCK,
    output wire [3:0]                       m_axi_port2_AWCACHE,
    output wire [2:0]                       m_axi_port2_AWPROT,
    output wire [3:0]                       m_axi_port2_AWQOS,
    output wire                             m_axi_port2_AWVALID,
    input  wire                             m_axi_port2_AWREADY,
    output wire [C_M_AXI_DATA_WIDTH-1:0]   m_axi_port2_WDATA,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_port2_WSTRB,
    output wire                             m_axi_port2_WLAST,
    output wire                             m_axi_port2_WVALID,
    input  wire                             m_axi_port2_WREADY,
    input  wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port2_BID,
    input  wire [1:0]                       m_axi_port2_BRESP,
    input  wire                             m_axi_port2_BVALID,
    output wire                             m_axi_port2_BREADY,
    output wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port2_ARID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]   m_axi_port2_ARADDR,
    output wire [7:0]                       m_axi_port2_ARLEN,
    output wire [2:0]                       m_axi_port2_ARSIZE,
    output wire [1:0]                       m_axi_port2_ARBURST,
    output wire                             m_axi_port2_ARLOCK,
    output wire [3:0]                       m_axi_port2_ARCACHE,
    output wire [2:0]                       m_axi_port2_ARPROT,
    output wire [3:0]                       m_axi_port2_ARQOS,
    output wire                             m_axi_port2_ARVALID,
    input  wire                             m_axi_port2_ARREADY,
    input  wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port2_RID,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]   m_axi_port2_RDATA,
    input  wire [1:0]                       m_axi_port2_RRESP,
    input  wire                             m_axi_port2_RLAST,
    input  wire                             m_axi_port2_RVALID,
    output wire                             m_axi_port2_RREADY,

    // -----------------------------------------------------------------------
    // AXI4 Full Master Port 3 (connect to PS HP3)
    // -----------------------------------------------------------------------
    output wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port3_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]   m_axi_port3_AWADDR,
    output wire [7:0]                       m_axi_port3_AWLEN,
    output wire [2:0]                       m_axi_port3_AWSIZE,
    output wire [1:0]                       m_axi_port3_AWBURST,
    output wire                             m_axi_port3_AWLOCK,
    output wire [3:0]                       m_axi_port3_AWCACHE,
    output wire [2:0]                       m_axi_port3_AWPROT,
    output wire [3:0]                       m_axi_port3_AWQOS,
    output wire                             m_axi_port3_AWVALID,
    input  wire                             m_axi_port3_AWREADY,
    output wire [C_M_AXI_DATA_WIDTH-1:0]   m_axi_port3_WDATA,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_port3_WSTRB,
    output wire                             m_axi_port3_WLAST,
    output wire                             m_axi_port3_WVALID,
    input  wire                             m_axi_port3_WREADY,
    input  wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port3_BID,
    input  wire [1:0]                       m_axi_port3_BRESP,
    input  wire                             m_axi_port3_BVALID,
    output wire                             m_axi_port3_BREADY,
    output wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port3_ARID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0]   m_axi_port3_ARADDR,
    output wire [7:0]                       m_axi_port3_ARLEN,
    output wire [2:0]                       m_axi_port3_ARSIZE,
    output wire [1:0]                       m_axi_port3_ARBURST,
    output wire                             m_axi_port3_ARLOCK,
    output wire [3:0]                       m_axi_port3_ARCACHE,
    output wire [2:0]                       m_axi_port3_ARPROT,
    output wire [3:0]                       m_axi_port3_ARQOS,
    output wire                             m_axi_port3_ARVALID,
    input  wire                             m_axi_port3_ARREADY,
    input  wire [C_M_AXI_ID_WIDTH-1:0]     m_axi_port3_RID,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]   m_axi_port3_RDATA,
    input  wire [1:0]                       m_axi_port3_RRESP,
    input  wire                             m_axi_port3_RLAST,
    input  wire                             m_axi_port3_RVALID,
    output wire                             m_axi_port3_RREADY
);

    // -----------------------------------------------------------------------
    // Internal wires from register controller
    // -----------------------------------------------------------------------
    wire        start_pulse;
    wire        stop_req;
    wire        sw_reset;
    wire [1:0]  mode;
    wire [7:0]  burst_len;
    wire [15:0] total_bursts;
    wire [63:0] p0_base_addr, p1_base_addr, p2_base_addr, p3_base_addr;

    // Per-port mode selection
    // mode=00: all read; mode=01: all write; mode=10: 0,1 read / 2,3 write
    wire port0_mode = (mode == 2'b01) ? 1'b1 : 1'b0;
    wire port1_mode = (mode == 2'b01) ? 1'b1 : 1'b0;
    wire port2_mode = (mode == 2'b00) ? 1'b0 : 1'b1;
    wire port3_mode = (mode == 2'b00) ? 1'b0 : 1'b1;

    // Per-port status wires (live, from traffic generators)
    wire [3:0]  port_done, port_active, port_error;
    wire [31:0] p0_beat_live, p1_beat_live, p2_beat_live, p3_beat_live;
    wire [31:0] p0_burst_live, p1_burst_live, p2_burst_live, p3_burst_live;

    // Frozen counter outputs (from ddr_bw_counter)
    wire [63:0] cycle_count;
    wire [31:0] p0_beat_cnt, p1_beat_cnt, p2_beat_cnt, p3_beat_cnt;
    wire [31:0] p0_burst_cnt, p1_burst_cnt, p2_burst_cnt, p3_burst_cnt;
    wire        all_done;

    // Internal reset: combine hardware resetn and software reset
    wire internal_resetn = aresetn & ~sw_reset;

    // -----------------------------------------------------------------------
    // AXI-Lite Register Controller
    // -----------------------------------------------------------------------
    ddr_bw_reg_ctrl #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_CTRL_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_CTRL_ADDR_WIDTH)
    ) u_reg_ctrl (
        .start_pulse     (start_pulse),
        .stop_req        (stop_req),
        .sw_reset        (sw_reset),
        .mode            (mode),
        .burst_len       (burst_len),
        .total_bursts    (total_bursts),
        .p0_base_addr    (p0_base_addr),
        .p1_base_addr    (p1_base_addr),
        .p2_base_addr    (p2_base_addr),
        .p3_base_addr    (p3_base_addr),
        .port_done       (port_done),
        .port_active     (port_active),
        .all_done        (all_done),
        .any_error       (|port_error),
        .cycle_count     (cycle_count),
        .p0_beat_cnt     (p0_beat_cnt),
        .p1_beat_cnt     (p1_beat_cnt),
        .p2_beat_cnt     (p2_beat_cnt),
        .p3_beat_cnt     (p3_beat_cnt),
        .p0_burst_cnt    (p0_burst_cnt),
        .p1_burst_cnt    (p1_burst_cnt),
        .p2_burst_cnt    (p2_burst_cnt),
        .p3_burst_cnt    (p3_burst_cnt),
        .S_AXI_ACLK      (aclk),
        .S_AXI_ARESETN   (aresetn),
        .S_AXI_AWADDR    (s_axi_ctrl_AWADDR),
        .S_AXI_AWPROT    (s_axi_ctrl_AWPROT),
        .S_AXI_AWVALID   (s_axi_ctrl_AWVALID),
        .S_AXI_AWREADY   (s_axi_ctrl_AWREADY),
        .S_AXI_WDATA     (s_axi_ctrl_WDATA),
        .S_AXI_WSTRB     (s_axi_ctrl_WSTRB),
        .S_AXI_WVALID    (s_axi_ctrl_WVALID),
        .S_AXI_WREADY    (s_axi_ctrl_WREADY),
        .S_AXI_BRESP     (s_axi_ctrl_BRESP),
        .S_AXI_BVALID    (s_axi_ctrl_BVALID),
        .S_AXI_BREADY    (s_axi_ctrl_BREADY),
        .S_AXI_ARADDR    (s_axi_ctrl_ARADDR),
        .S_AXI_ARPROT    (s_axi_ctrl_ARPROT),
        .S_AXI_ARVALID   (s_axi_ctrl_ARVALID),
        .S_AXI_ARREADY   (s_axi_ctrl_ARREADY),
        .S_AXI_RDATA     (s_axi_ctrl_RDATA),
        .S_AXI_RRESP     (s_axi_ctrl_RRESP),
        .S_AXI_RVALID    (s_axi_ctrl_RVALID),
        .S_AXI_RREADY    (s_axi_ctrl_RREADY)
    );

    // -----------------------------------------------------------------------
    // Traffic Generator Port 0
    // -----------------------------------------------------------------------
    ddr_bw_traffic_gen #(
        .PORT_ID           (0),
        .C_M_AXI_ID_WIDTH  (C_M_AXI_ID_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH)
    ) u_tgen0 (
        .clk            (aclk),
        .resetn         (internal_resetn),
        .start_pulse    (start_pulse),
        .stop_req       (stop_req),
        .mode           (port0_mode),
        .base_addr      (p0_base_addr),
        .burst_len      (burst_len),
        .total_bursts   (total_bursts),
        .done           (port_done[0]),
        .active         (port_active[0]),
        .error          (port_error[0]),
        .beat_cnt       (p0_beat_live),
        .burst_cnt      (p0_burst_live),
        .M_AXI_AWID     (m_axi_port0_AWID),
        .M_AXI_AWADDR   (m_axi_port0_AWADDR),
        .M_AXI_AWLEN    (m_axi_port0_AWLEN),
        .M_AXI_AWSIZE   (m_axi_port0_AWSIZE),
        .M_AXI_AWBURST  (m_axi_port0_AWBURST),
        .M_AXI_AWLOCK   (m_axi_port0_AWLOCK),
        .M_AXI_AWCACHE  (m_axi_port0_AWCACHE),
        .M_AXI_AWPROT   (m_axi_port0_AWPROT),
        .M_AXI_AWQOS    (m_axi_port0_AWQOS),
        .M_AXI_AWVALID  (m_axi_port0_AWVALID),
        .M_AXI_AWREADY  (m_axi_port0_AWREADY),
        .M_AXI_WDATA    (m_axi_port0_WDATA),
        .M_AXI_WSTRB    (m_axi_port0_WSTRB),
        .M_AXI_WLAST    (m_axi_port0_WLAST),
        .M_AXI_WVALID   (m_axi_port0_WVALID),
        .M_AXI_WREADY   (m_axi_port0_WREADY),
        .M_AXI_BID      (m_axi_port0_BID),
        .M_AXI_BRESP    (m_axi_port0_BRESP),
        .M_AXI_BVALID   (m_axi_port0_BVALID),
        .M_AXI_BREADY   (m_axi_port0_BREADY),
        .M_AXI_ARID     (m_axi_port0_ARID),
        .M_AXI_ARADDR   (m_axi_port0_ARADDR),
        .M_AXI_ARLEN    (m_axi_port0_ARLEN),
        .M_AXI_ARSIZE   (m_axi_port0_ARSIZE),
        .M_AXI_ARBURST  (m_axi_port0_ARBURST),
        .M_AXI_ARLOCK   (m_axi_port0_ARLOCK),
        .M_AXI_ARCACHE  (m_axi_port0_ARCACHE),
        .M_AXI_ARPROT   (m_axi_port0_ARPROT),
        .M_AXI_ARQOS    (m_axi_port0_ARQOS),
        .M_AXI_ARVALID  (m_axi_port0_ARVALID),
        .M_AXI_ARREADY  (m_axi_port0_ARREADY),
        .M_AXI_RID      (m_axi_port0_RID),
        .M_AXI_RDATA    (m_axi_port0_RDATA),
        .M_AXI_RRESP    (m_axi_port0_RRESP),
        .M_AXI_RLAST    (m_axi_port0_RLAST),
        .M_AXI_RVALID   (m_axi_port0_RVALID),
        .M_AXI_RREADY   (m_axi_port0_RREADY)
    );

    // -----------------------------------------------------------------------
    // Traffic Generator Port 1
    // -----------------------------------------------------------------------
    ddr_bw_traffic_gen #(
        .PORT_ID           (1),
        .C_M_AXI_ID_WIDTH  (C_M_AXI_ID_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH)
    ) u_tgen1 (
        .clk            (aclk),
        .resetn         (internal_resetn),
        .start_pulse    (start_pulse),
        .stop_req       (stop_req),
        .mode           (port1_mode),
        .base_addr      (p1_base_addr),
        .burst_len      (burst_len),
        .total_bursts   (total_bursts),
        .done           (port_done[1]),
        .active         (port_active[1]),
        .error          (port_error[1]),
        .beat_cnt       (p1_beat_live),
        .burst_cnt      (p1_burst_live),
        .M_AXI_AWID     (m_axi_port1_AWID),
        .M_AXI_AWADDR   (m_axi_port1_AWADDR),
        .M_AXI_AWLEN    (m_axi_port1_AWLEN),
        .M_AXI_AWSIZE   (m_axi_port1_AWSIZE),
        .M_AXI_AWBURST  (m_axi_port1_AWBURST),
        .M_AXI_AWLOCK   (m_axi_port1_AWLOCK),
        .M_AXI_AWCACHE  (m_axi_port1_AWCACHE),
        .M_AXI_AWPROT   (m_axi_port1_AWPROT),
        .M_AXI_AWQOS    (m_axi_port1_AWQOS),
        .M_AXI_AWVALID  (m_axi_port1_AWVALID),
        .M_AXI_AWREADY  (m_axi_port1_AWREADY),
        .M_AXI_WDATA    (m_axi_port1_WDATA),
        .M_AXI_WSTRB    (m_axi_port1_WSTRB),
        .M_AXI_WLAST    (m_axi_port1_WLAST),
        .M_AXI_WVALID   (m_axi_port1_WVALID),
        .M_AXI_WREADY   (m_axi_port1_WREADY),
        .M_AXI_BID      (m_axi_port1_BID),
        .M_AXI_BRESP    (m_axi_port1_BRESP),
        .M_AXI_BVALID   (m_axi_port1_BVALID),
        .M_AXI_BREADY   (m_axi_port1_BREADY),
        .M_AXI_ARID     (m_axi_port1_ARID),
        .M_AXI_ARADDR   (m_axi_port1_ARADDR),
        .M_AXI_ARLEN    (m_axi_port1_ARLEN),
        .M_AXI_ARSIZE   (m_axi_port1_ARSIZE),
        .M_AXI_ARBURST  (m_axi_port1_ARBURST),
        .M_AXI_ARLOCK   (m_axi_port1_ARLOCK),
        .M_AXI_ARCACHE  (m_axi_port1_ARCACHE),
        .M_AXI_ARPROT   (m_axi_port1_ARPROT),
        .M_AXI_ARQOS    (m_axi_port1_ARQOS),
        .M_AXI_ARVALID  (m_axi_port1_ARVALID),
        .M_AXI_ARREADY  (m_axi_port1_ARREADY),
        .M_AXI_RID      (m_axi_port1_RID),
        .M_AXI_RDATA    (m_axi_port1_RDATA),
        .M_AXI_RRESP    (m_axi_port1_RRESP),
        .M_AXI_RLAST    (m_axi_port1_RLAST),
        .M_AXI_RVALID   (m_axi_port1_RVALID),
        .M_AXI_RREADY   (m_axi_port1_RREADY)
    );

    // -----------------------------------------------------------------------
    // Traffic Generator Port 2
    // -----------------------------------------------------------------------
    ddr_bw_traffic_gen #(
        .PORT_ID           (2),
        .C_M_AXI_ID_WIDTH  (C_M_AXI_ID_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH)
    ) u_tgen2 (
        .clk            (aclk),
        .resetn         (internal_resetn),
        .start_pulse    (start_pulse),
        .stop_req       (stop_req),
        .mode           (port2_mode),
        .base_addr      (p2_base_addr),
        .burst_len      (burst_len),
        .total_bursts   (total_bursts),
        .done           (port_done[2]),
        .active         (port_active[2]),
        .error          (port_error[2]),
        .beat_cnt       (p2_beat_live),
        .burst_cnt      (p2_burst_live),
        .M_AXI_AWID     (m_axi_port2_AWID),
        .M_AXI_AWADDR   (m_axi_port2_AWADDR),
        .M_AXI_AWLEN    (m_axi_port2_AWLEN),
        .M_AXI_AWSIZE   (m_axi_port2_AWSIZE),
        .M_AXI_AWBURST  (m_axi_port2_AWBURST),
        .M_AXI_AWLOCK   (m_axi_port2_AWLOCK),
        .M_AXI_AWCACHE  (m_axi_port2_AWCACHE),
        .M_AXI_AWPROT   (m_axi_port2_AWPROT),
        .M_AXI_AWQOS    (m_axi_port2_AWQOS),
        .M_AXI_AWVALID  (m_axi_port2_AWVALID),
        .M_AXI_AWREADY  (m_axi_port2_AWREADY),
        .M_AXI_WDATA    (m_axi_port2_WDATA),
        .M_AXI_WSTRB    (m_axi_port2_WSTRB),
        .M_AXI_WLAST    (m_axi_port2_WLAST),
        .M_AXI_WVALID   (m_axi_port2_WVALID),
        .M_AXI_WREADY   (m_axi_port2_WREADY),
        .M_AXI_BID      (m_axi_port2_BID),
        .M_AXI_BRESP    (m_axi_port2_BRESP),
        .M_AXI_BVALID   (m_axi_port2_BVALID),
        .M_AXI_BREADY   (m_axi_port2_BREADY),
        .M_AXI_ARID     (m_axi_port2_ARID),
        .M_AXI_ARADDR   (m_axi_port2_ARADDR),
        .M_AXI_ARLEN    (m_axi_port2_ARLEN),
        .M_AXI_ARSIZE   (m_axi_port2_ARSIZE),
        .M_AXI_ARBURST  (m_axi_port2_ARBURST),
        .M_AXI_ARLOCK   (m_axi_port2_ARLOCK),
        .M_AXI_ARCACHE  (m_axi_port2_ARCACHE),
        .M_AXI_ARPROT   (m_axi_port2_ARPROT),
        .M_AXI_ARQOS    (m_axi_port2_ARQOS),
        .M_AXI_ARVALID  (m_axi_port2_ARVALID),
        .M_AXI_ARREADY  (m_axi_port2_ARREADY),
        .M_AXI_RID      (m_axi_port2_RID),
        .M_AXI_RDATA    (m_axi_port2_RDATA),
        .M_AXI_RRESP    (m_axi_port2_RRESP),
        .M_AXI_RLAST    (m_axi_port2_RLAST),
        .M_AXI_RVALID   (m_axi_port2_RVALID),
        .M_AXI_RREADY   (m_axi_port2_RREADY)
    );

    // -----------------------------------------------------------------------
    // Traffic Generator Port 3
    // -----------------------------------------------------------------------
    ddr_bw_traffic_gen #(
        .PORT_ID           (3),
        .C_M_AXI_ID_WIDTH  (C_M_AXI_ID_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH)
    ) u_tgen3 (
        .clk            (aclk),
        .resetn         (internal_resetn),
        .start_pulse    (start_pulse),
        .stop_req       (stop_req),
        .mode           (port3_mode),
        .base_addr      (p3_base_addr),
        .burst_len      (burst_len),
        .total_bursts   (total_bursts),
        .done           (port_done[3]),
        .active         (port_active[3]),
        .error          (port_error[3]),
        .beat_cnt       (p3_beat_live),
        .burst_cnt      (p3_burst_live),
        .M_AXI_AWID     (m_axi_port3_AWID),
        .M_AXI_AWADDR   (m_axi_port3_AWADDR),
        .M_AXI_AWLEN    (m_axi_port3_AWLEN),
        .M_AXI_AWSIZE   (m_axi_port3_AWSIZE),
        .M_AXI_AWBURST  (m_axi_port3_AWBURST),
        .M_AXI_AWLOCK   (m_axi_port3_AWLOCK),
        .M_AXI_AWCACHE  (m_axi_port3_AWCACHE),
        .M_AXI_AWPROT   (m_axi_port3_AWPROT),
        .M_AXI_AWQOS    (m_axi_port3_AWQOS),
        .M_AXI_AWVALID  (m_axi_port3_AWVALID),
        .M_AXI_AWREADY  (m_axi_port3_AWREADY),
        .M_AXI_WDATA    (m_axi_port3_WDATA),
        .M_AXI_WSTRB    (m_axi_port3_WSTRB),
        .M_AXI_WLAST    (m_axi_port3_WLAST),
        .M_AXI_WVALID   (m_axi_port3_WVALID),
        .M_AXI_WREADY   (m_axi_port3_WREADY),
        .M_AXI_BID      (m_axi_port3_BID),
        .M_AXI_BRESP    (m_axi_port3_BRESP),
        .M_AXI_BVALID   (m_axi_port3_BVALID),
        .M_AXI_BREADY   (m_axi_port3_BREADY),
        .M_AXI_ARID     (m_axi_port3_ARID),
        .M_AXI_ARADDR   (m_axi_port3_ARADDR),
        .M_AXI_ARLEN    (m_axi_port3_ARLEN),
        .M_AXI_ARSIZE   (m_axi_port3_ARSIZE),
        .M_AXI_ARBURST  (m_axi_port3_ARBURST),
        .M_AXI_ARLOCK   (m_axi_port3_ARLOCK),
        .M_AXI_ARCACHE  (m_axi_port3_ARCACHE),
        .M_AXI_ARPROT   (m_axi_port3_ARPROT),
        .M_AXI_ARQOS    (m_axi_port3_ARQOS),
        .M_AXI_ARVALID  (m_axi_port3_ARVALID),
        .M_AXI_ARREADY  (m_axi_port3_ARREADY),
        .M_AXI_RID      (m_axi_port3_RID),
        .M_AXI_RDATA    (m_axi_port3_RDATA),
        .M_AXI_RRESP    (m_axi_port3_RRESP),
        .M_AXI_RLAST    (m_axi_port3_RLAST),
        .M_AXI_RVALID   (m_axi_port3_RVALID),
        .M_AXI_RREADY   (m_axi_port3_RREADY)
    );

    // -----------------------------------------------------------------------
    // Bandwidth Counter
    // -----------------------------------------------------------------------
    ddr_bw_counter u_counter (
        .clk           (aclk),
        .resetn        (aresetn),
        .sw_reset      (sw_reset),
        .start_pulse   (start_pulse),
        .port_done     (port_done),
        .port_active   (port_active),
        .p0_beat_live  (p0_beat_live),
        .p1_beat_live  (p1_beat_live),
        .p2_beat_live  (p2_beat_live),
        .p3_beat_live  (p3_beat_live),
        .p0_burst_live (p0_burst_live),
        .p1_burst_live (p1_burst_live),
        .p2_burst_live (p2_burst_live),
        .p3_burst_live (p3_burst_live),
        .cycle_count   (cycle_count),
        .p0_beat_cnt   (p0_beat_cnt),
        .p1_beat_cnt   (p1_beat_cnt),
        .p2_beat_cnt   (p2_beat_cnt),
        .p3_beat_cnt   (p3_beat_cnt),
        .p0_burst_cnt  (p0_burst_cnt),
        .p1_burst_cnt  (p1_burst_cnt),
        .p2_burst_cnt  (p2_burst_cnt),
        .p3_burst_cnt  (p3_burst_cnt),
        .all_done      (all_done)
    );

endmodule
