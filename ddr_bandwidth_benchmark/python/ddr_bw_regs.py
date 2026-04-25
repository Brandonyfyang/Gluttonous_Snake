"""
DDR Bandwidth Benchmark - Register Map Definitions

Mirrors the register map in ddr_bw_reg_ctrl.v.
Use these constants when accessing the AXI-Lite control interface from Python/PYNQ.

Register layout (7-bit AXI-Lite address, 32-bit data):
    All offsets are byte offsets from the IP base address.
"""

# ---------------------------------------------------------------------------
# Register byte offsets
# ---------------------------------------------------------------------------
REG_CTRL          = 0x00   # Control register (R/W)
REG_STATUS        = 0x04   # Status register (R)
REG_BURST_LEN     = 0x08   # Beats per burst (R/W)
REG_TOTAL_BURSTS  = 0x0C   # Total bursts per port (R/W)
REG_P0_BASE_LOW   = 0x10   # Port 0 DDR base address [31:0] (R/W)
REG_P0_BASE_HIGH  = 0x14   # Port 0 DDR base address [63:32] (R/W)
REG_P1_BASE_LOW   = 0x18   # Port 1 DDR base address [31:0] (R/W)
REG_P1_BASE_HIGH  = 0x1C   # Port 1 DDR base address [63:32] (R/W)
REG_P2_BASE_LOW   = 0x20   # Port 2 DDR base address [31:0] (R/W)
REG_P2_BASE_HIGH  = 0x24   # Port 2 DDR base address [63:32] (R/W)
REG_P3_BASE_LOW   = 0x28   # Port 3 DDR base address [31:0] (R/W)
REG_P3_BASE_HIGH  = 0x2C   # Port 3 DDR base address [63:32] (R/W)
REG_CYCLE_CNT_L   = 0x30   # Elapsed hardware cycles [31:0] (R)
REG_CYCLE_CNT_H   = 0x34   # Elapsed hardware cycles [63:32] (R)
REG_P0_BEAT_CNT   = 0x38   # Port 0 completed beat count (R)
REG_P1_BEAT_CNT   = 0x3C   # Port 1 completed beat count (R)
REG_P2_BEAT_CNT   = 0x40   # Port 2 completed beat count (R)
REG_P3_BEAT_CNT   = 0x44   # Port 3 completed beat count (R)
REG_P0_BURST_CNT  = 0x48   # Port 0 completed burst count (R)
REG_P1_BURST_CNT  = 0x4C   # Port 1 completed burst count (R)
REG_P2_BURST_CNT  = 0x50   # Port 2 completed burst count (R)
REG_P3_BURST_CNT  = 0x54   # Port 3 completed burst count (R)

# ---------------------------------------------------------------------------
# CTRL register bit fields (offset 0x00)
# ---------------------------------------------------------------------------
CTRL_START        = (1 << 0)   # Write 1 to start benchmark (self-clearing)
CTRL_STOP         = (1 << 1)   # Write 1 to request graceful stop
CTRL_SW_RESET     = (1 << 2)   # Write 1 for synchronous reset of all engines
CTRL_MODE_SHIFT   = 4          # Mode field starts at bit 4
CTRL_MODE_MASK    = 0x3        # 2-bit mode field

# ---------------------------------------------------------------------------
# MODE values (CTRL[5:4])
# ---------------------------------------------------------------------------
MODE_READ         = 0b00   # All 4 ports issue AXI read bursts
MODE_WRITE        = 0b01   # All 4 ports issue AXI write bursts
MODE_RD_WR_SPLIT  = 0b10   # Ports 0,1 read; ports 2,3 write

MODE_NAMES = {
    MODE_READ:        "READ",
    MODE_WRITE:       "WRITE",
    MODE_RD_WR_SPLIT: "RD_WR_SPLIT",
}

# ---------------------------------------------------------------------------
# STATUS register bit fields (offset 0x04)
# ---------------------------------------------------------------------------
STATUS_PORT_DONE_SHIFT   = 0    # bits [3:0] = per-port done flags
STATUS_PORT_DONE_MASK    = 0xF
STATUS_PORT_ACTIVE_SHIFT = 4    # bits [7:4] = per-port active flags
STATUS_PORT_ACTIVE_MASK  = 0xF
STATUS_ALL_DONE          = (1 << 8)   # all 4 ports completed
STATUS_ANY_ERROR         = (1 << 9)   # any AXI error detected

# ---------------------------------------------------------------------------
# Hardware constants matching RTL defaults
# ---------------------------------------------------------------------------
DEFAULT_BURST_LEN    = 16     # beats per burst
DEFAULT_TOTAL_BURSTS = 256    # total bursts per port
AXI_DATA_WIDTH_BYTES = 8      # 64-bit AXI data bus = 8 bytes per beat

# ---------------------------------------------------------------------------
# Helper: compute bytes transferred per port
# ---------------------------------------------------------------------------
def bytes_per_port(beat_cnt: int, data_width_bytes: int = AXI_DATA_WIDTH_BYTES) -> int:
    """Return total bytes transferred by one port given its beat count."""
    return beat_cnt * data_width_bytes


# ---------------------------------------------------------------------------
# Register map summary (for documentation / introspection)
# ---------------------------------------------------------------------------
REGISTER_MAP = {
    REG_CTRL:         ("CTRL",         "R/W", "Control: [0]=start,[1]=stop,[2]=sw_reset,[5:4]=mode"),
    REG_STATUS:       ("STATUS",       "R",   "Status: [3:0]=done,[7:4]=active,[8]=all_done,[9]=error"),
    REG_BURST_LEN:    ("BURST_LEN",    "R/W", "Beats per burst [7:0], default 16"),
    REG_TOTAL_BURSTS: ("TOTAL_BURSTS", "R/W", "Total bursts per port [15:0], default 256"),
    REG_P0_BASE_LOW:  ("P0_BASE_LOW",  "R/W", "Port 0 base address [31:0]"),
    REG_P0_BASE_HIGH: ("P0_BASE_HIGH", "R/W", "Port 0 base address [63:32]"),
    REG_P1_BASE_LOW:  ("P1_BASE_LOW",  "R/W", "Port 1 base address [31:0]"),
    REG_P1_BASE_HIGH: ("P1_BASE_HIGH", "R/W", "Port 1 base address [63:32]"),
    REG_P2_BASE_LOW:  ("P2_BASE_LOW",  "R/W", "Port 2 base address [31:0]"),
    REG_P2_BASE_HIGH: ("P2_BASE_HIGH", "R/W", "Port 2 base address [63:32]"),
    REG_P3_BASE_LOW:  ("P3_BASE_LOW",  "R/W", "Port 3 base address [31:0]"),
    REG_P3_BASE_HIGH: ("P3_BASE_HIGH", "R/W", "Port 3 base address [63:32]"),
    REG_CYCLE_CNT_L:  ("CYCLE_CNT_L",  "R",  "Elapsed cycles [31:0]"),
    REG_CYCLE_CNT_H:  ("CYCLE_CNT_H",  "R",  "Elapsed cycles [63:32]"),
    REG_P0_BEAT_CNT:  ("P0_BEAT_CNT",  "R",  "Port 0 beat count"),
    REG_P1_BEAT_CNT:  ("P1_BEAT_CNT",  "R",  "Port 1 beat count"),
    REG_P2_BEAT_CNT:  ("P2_BEAT_CNT",  "R",  "Port 2 beat count"),
    REG_P3_BEAT_CNT:  ("P3_BEAT_CNT",  "R",  "Port 3 beat count"),
    REG_P0_BURST_CNT: ("P0_BURST_CNT", "R",  "Port 0 burst count"),
    REG_P1_BURST_CNT: ("P1_BURST_CNT", "R",  "Port 1 burst count"),
    REG_P2_BURST_CNT: ("P2_BURST_CNT", "R",  "Port 2 burst count"),
    REG_P3_BURST_CNT: ("P3_BURST_CNT", "R",  "Port 3 burst count"),
}


def print_register_map():
    """Print the register map table to stdout."""
    print(f"{'Offset':>8}  {'Name':<16}  {'RW':<4}  Description")
    print("-" * 70)
    for offset, (name, rw, desc) in sorted(REGISTER_MAP.items()):
        print(f"  0x{offset:04X}  {name:<16}  {rw:<4}  {desc}")
