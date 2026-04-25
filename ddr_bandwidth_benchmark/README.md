# DDR Bandwidth Benchmark — KV260 / PYNQ Reference Project

A reusable, board-ready reference design for measuring PS DDR memory bandwidth
from the PL side on KV260 (and other PYNQ-compatible Zynq/Zynq-UltraScale+ boards).

Built from and inspired by the existing repository patterns:
- AXI-Lite register controller adapted from `rtl/axi/axi_lite_configs.v`
- AXI4 Full Master traffic generator adapted from `rtl/axi/axi_full_master_r.v` / `axi_full_master_w.v`
- Multi-port top-level structure adapted from `rtl/acc_control.sv`
- PYNQ interaction style adapted from `jupyter_test/basic_test/activation_accelerator.ipynb`

---

## Directory Structure

```
ddr_bandwidth_benchmark/
├── hardware/
│   └── rtl/
│       ├── ddr_bw_top.v          Top-level integration (instantiates all sub-modules)
│       ├── ddr_bw_reg_ctrl.v     AXI4-Lite register block (config + status)
│       ├── ddr_bw_traffic_gen.v  AXI4 Full Master traffic generator (per-port)
│       └── ddr_bw_counter.v      Hardware bandwidth/cycle counter
├── python/
│   ├── ddr_bw_regs.py            Register map constants and field definitions
│   └── ddr_bw_benchmark.py       PYNQ Python driver class
├── notebooks/
│   └── ddr_bw_benchmark.ipynb   Example Jupyter notebook with sweep and plots
└── README.md                     This file
```

---

## Architecture Overview

```
  PS (ARM)                         PL (Zynq/Zynq-UltraScale+)
  ─────────────────────            ──────────────────────────────────────────────────
  GP AXI-Lite Master  ──────────►  ddr_bw_reg_ctrl  (AXI4-Lite Slave, 7-bit addr)
                                        │
                                   ┌────┴────────────────────────────────────┐
                                   │ config: start, mode, burst_len,         │
                                   │         total_bursts, port_base[0..3]   │
                                   └────┬────────────────────────────────────┘
                                        │ (start_pulse, config wires)
                              ┌─────────┼─────────────────────────┐
                              ▼         ▼         ▼               ▼
                         tgen0       tgen1       tgen2          tgen3
                     (port 0)    (port 1)    (port 2)       (port 3)
                         │           │           │               │
                     AXI4 Full   AXI4 Full   AXI4 Full      AXI4 Full
                     Master      Master      Master         Master
                         │           │           │               │
  HP0 ◄──────────────────┘           │           │               │
  HP1 ◄──────────────────────────────┘           │               │
  HP2 ◄────────────────────────────────────────── ┘              │
  HP3 ◄─────────────────────────────────────────────────────────┘
         (all to PS DDR via HP slave ports)

                              ┌───────────────────┐
                              │   ddr_bw_counter   │
                              │  cycle count,      │
                              │  beat/burst latch  │
                              └────────┬───────────┘
                                       │ (cycle_count, beat_cnt, burst_cnt)
                                       ▼
                               ddr_bw_reg_ctrl (STATUS + counter regs)
                                       │
  GP AXI-Lite Master  ◄───────────────┘  (PS reads results)
```

### Module Hierarchy

| Module | File | Description |
|--------|------|-------------|
| `ddr_bw_top` | `ddr_bw_top.v` | Top-level. Instantiates all sub-modules and routes signals. |
| `ddr_bw_reg_ctrl` | `ddr_bw_reg_ctrl.v` | AXI4-Lite slave. Exposes 32 × 32-bit registers for config and status. |
| `ddr_bw_traffic_gen` | `ddr_bw_traffic_gen.v` | AXI4 Full Master. Issues configurable read or write burst sequences. Parameterized per port. |
| `ddr_bw_counter` | `ddr_bw_counter.v` | Counts PL clock cycles from start to all-done. Latches per-port beat/burst counts at completion. |

---

## Register Map

All registers are 32-bit wide, accessed via the AXI4-Lite slave interface.
The IP base address is assigned by Vivado block design (typically `0xA000_0000`).

| Byte Offset | Name | R/W | Description |
|-------------|------|-----|-------------|
| 0x00 | `CTRL` | R/W | **Control register**. Write to configure and start. |
| 0x04 | `STATUS` | R | **Status register**. Read to check completion and errors. |
| 0x08 | `BURST_LEN` | R/W | AXI burst length in beats `[7:0]`. Default 16. |
| 0x0C | `TOTAL_BURSTS` | R/W | Total bursts per port `[15:0]`. Default 256. |
| 0x10 | `P0_BASE_LOW` | R/W | Port 0 DDR base address bits `[31:0]`. |
| 0x14 | `P0_BASE_HIGH` | R/W | Port 0 DDR base address bits `[63:32]`. |
| 0x18 | `P1_BASE_LOW` | R/W | Port 1 DDR base address bits `[31:0]`. |
| 0x1C | `P1_BASE_HIGH` | R/W | Port 1 DDR base address bits `[63:32]`. |
| 0x20 | `P2_BASE_LOW` | R/W | Port 2 DDR base address bits `[31:0]`. |
| 0x24 | `P2_BASE_HIGH` | R/W | Port 2 DDR base address bits `[63:32]`. |
| 0x28 | `P3_BASE_LOW` | R/W | Port 3 DDR base address bits `[31:0]`. |
| 0x2C | `P3_BASE_HIGH` | R/W | Port 3 DDR base address bits `[63:32]`. |
| 0x30 | `CYCLE_CNT_L` | R | Elapsed PL clock cycles `[31:0]` (captured at completion). |
| 0x34 | `CYCLE_CNT_H` | R | Elapsed PL clock cycles `[63:32]`. |
| 0x38 | `P0_BEAT_CNT` | R | Port 0 completed beat count. |
| 0x3C | `P1_BEAT_CNT` | R | Port 1 completed beat count. |
| 0x40 | `P2_BEAT_CNT` | R | Port 2 completed beat count. |
| 0x44 | `P3_BEAT_CNT` | R | Port 3 completed beat count. |
| 0x48 | `P0_BURST_CNT` | R | Port 0 completed burst count. |
| 0x4C | `P1_BURST_CNT` | R | Port 1 completed burst count. |
| 0x50 | `P2_BURST_CNT` | R | Port 2 completed burst count. |
| 0x54 | `P3_BURST_CNT` | R | Port 3 completed burst count. |
| 0x58–0x7C | (reserved) | — | Reserved for future use. |

### CTRL Register Bit Fields (0x00)

| Bit(s) | Field | Description |
|--------|-------|-------------|
| `[0]` | `START` | Write 1 to start the benchmark. **Self-clearing** (hardware clears after one cycle). |
| `[1]` | `STOP` | Write 1 to request a graceful stop of all traffic generators. |
| `[2]` | `SW_RESET` | Write 1 to synchronously reset all traffic generators and counters. Write 0 to deassert. |
| `[5:4]` | `MODE` | Transfer mode. See table below. |

### MODE Values

| Value | Name | Description |
|-------|------|-------------|
| `2'b00` | `READ` | All 4 ports issue AXI4 read bursts from DDR. |
| `2'b01` | `WRITE` | All 4 ports issue AXI4 write bursts to DDR. |
| `2'b10` | `RD_WR_SPLIT` | Ports 0 and 1 read; ports 2 and 3 write. |

### STATUS Register Bit Fields (0x04)

| Bit(s) | Field | Description |
|--------|-------|-------------|
| `[3:0]` | `PORT_DONE` | Per-port completion flags (bit N = port N done). |
| `[7:4]` | `PORT_ACTIVE` | Per-port active flags (bit N+4 = port N active). |
| `[8]` | `ALL_DONE` | High when all 4 ports have completed. Poll this bit to detect completion. |
| `[9]` | `ANY_ERROR` | High if any port received a non-OKAY AXI response. |

---

## How the 4 Ports Work

Each `ddr_bw_traffic_gen` instance operates independently and identically.
All four ports are started simultaneously by the same `start_pulse`.

### Traffic Generator State Machine

```
IDLE ──(start_pulse)──► [latch config, reset counters]
                               │
                    mode=0     │     mode=1
                    (READ)     │     (WRITE)
                    ▼          │          ▼
                  ST_AR        │        ST_AW
          (send AR burst)      │  (send AW burst)
                    │          │          │
                  ST_R         │        ST_W
          (receive R data,     │  (send W data,
           count beats)        │   count beats)
                    │          │          │
             rlast+burst_done  │   wlast → ST_B
                    │          │  (wait B resp)
                    │          │          │
                  ──┴──────────┴──────────┘
                             │
                   more bursts? ──yes──► ST_AR / ST_AW
                             │
                            no
                             ▼
                           ST_DONE (assert done, increment burst_cnt)
```

### Address Sequencing

Each port starts at its configured base address and increments by
`burst_len × 8 bytes` (for 64-bit data width) after each completed burst.
Bursts wrap within the allocated buffer if `total_bursts × burst_len × 8B > buf_size`.

---

## Bandwidth Calculation

### Hardware Bandwidth

The `ddr_bw_counter` module counts PL clock cycles from the first `start_pulse`
until all four `port_done` flags are simultaneously high.

```
HW_time_s     = CYCLE_CNT / clk_freq_Hz
bytes_port[N] = P{N}_BEAT_CNT × AXI_DATA_WIDTH_BYTES   (= 8 for 64-bit bus)
total_bytes   = sum(bytes_port[0..3])

HW_aggregate_BW (GB/s) = total_bytes / HW_time_s / 1e9
HW_per_port_BW  (GB/s) = bytes_port[N] / HW_time_s / 1e9
```

> **Note:** `CYCLE_CNT` starts counting when `start_pulse` is seen and stops
> when **all** ports are done. If ports complete at different times (e.g. due to
> different buffer addresses or modes in `RD_WR_SPLIT`), the cycle count reflects
> the elapsed time until the **last** port finishes.

### Software Bandwidth

Measured by `time.perf_counter()` in Python, from just before writing
`CTRL_START` to when `STATUS[ALL_DONE]` is polled as set:

```
SW_BW (GB/s) = total_bytes / wall_time_s / 1e9
```

The software measurement includes Python polling overhead (~0.1 ms typical),
making it slightly lower than the hardware measurement for short runs.

### KV260 DDR4 Reference

| Metric | Value |
|--------|-------|
| DDR4 speed grade | 2400 MT/s |
| Bus width | 64-bit (single channel) |
| Theoretical peak | 19.2 GB/s |
| Practical PL achievable | ~11–16 GB/s (4 ports, burst_len ≥ 16) |
| Overhead sources | AXI interconnect latency, DDR controller scheduling, cache coherency |

---

## Software Quick-Start (PYNQ on KV260)

```python
from ddr_bw_benchmark import DDRBandwidthBenchmark, BenchmarkConfig
from ddr_bw_regs import MODE_READ, MODE_WRITE, MODE_RD_WR_SPLIT

# Load bitstream
bm = DDRBandwidthBenchmark('ddr_bw.bit')
bm.load()

# Read benchmark: 4 ports × 4096 bursts × 16 beats × 8B = 2 MB/port
cfg = BenchmarkConfig(
    mode=MODE_READ,
    burst_len=16,
    total_bursts=4096,
    buf_size_bytes=4 * 1024 * 1024,
    clk_freq_mhz=300.0,
)
results = bm.run(cfg)
DDRBandwidthBenchmark.print_results(results)

# Mixed read/write
cfg_mixed = BenchmarkConfig(mode=MODE_RD_WR_SPLIT, burst_len=16, total_bursts=4096)
results_mixed = bm.run(cfg_mixed)
DDRBandwidthBenchmark.print_results(results_mixed)

bm.close()
```

Expected output (approximate):
```
============================================================
  DDR Bandwidth Benchmark Results
============================================================
  Mode           : READ
  Burst length   : 16 beats
  Total bursts   : 4096 per port
  Bytes/port     : 0.50 MB
  PL clock       : 300.0 MHz
  ...
  HW agg BW      : 12.345 GB/s
  SW agg BW      : 12.201 GB/s
============================================================
```

---

## Vivado Block Design Integration (KV260)

### Step-by-step

1. Create a new Vivado project targeting the KV260 (`xck26-sfvc784-2LV-c`).
2. Add a block design.
3. Add the Zynq UltraScale+ MPSoC IP and run block automation.
4. Add the four RTL source files as HDL sources:
   - `ddr_bw_top.v`, `ddr_bw_reg_ctrl.v`, `ddr_bw_traffic_gen.v`, `ddr_bw_counter.v`
5. Add `ddr_bw_top` as an RTL module to the block design.
6. Connect `s_axi_ctrl` to the PS AXI-Lite Master (GP0 or GP1).
7. Connect each `m_axi_port0..3` to PS HP slave ports (HP0–HP3).
   - Enable HP0–HP3 in the Zynq IP configuration.
   - Set HP data width to 64-bit to match the RTL.
8. Connect `aclk` and `aresetn` from the Processor System Reset peripheral.
9. Run **Connection Automation** to add AXI Interconnects if needed.
10. Assign the AXI-Lite base address (e.g. `0xA000_0000`) via Address Editor.
11. Validate, synthesize, implement, and generate bitstream.
12. Export hardware (`.xsa`) to create the PYNQ `.hwh` metadata file.

### Port Width Note

The KV260 HP ports support 32-bit or 64-bit data widths. This design uses **64-bit**
(`C_M_AXI_DATA_WIDTH = 64`). Ensure the HP port AXI slave width is set to 64-bit in
the Zynq IP configuration to avoid width conversion overhead.

### Clock Frequency

The hardware reset `pl_clk0` on KV260 defaults to **100 MHz**. The Python `BenchmarkConfig`
defaults `clk_freq_mhz` to **300 MHz**, which is the recommended PL clock frequency for
bandwidth experiments. To use 300 MHz, configure it via the Zynq IP PL fabric clock settings
in Vivado or via a Clocking Wizard IP. Always set `clk_freq_mhz` in your Python config to
match the actual frequency used in your bitstream.

---

## Assumptions and Limitations

1. **No bitstream provided**: Synthesizing and implementing for KV260 requires
   Vivado 2022.x or later and the KV260 board files. The RTL is provided as a
   synthesizable reference; a pre-built bitstream is not included.

2. **Sequential bursts per port**: Each `ddr_bw_traffic_gen` issues one burst at
   a time (no outstanding burst pipelining). This is simpler but may not achieve
   the theoretical peak bandwidth. Adding outstanding-burst support would require
   a FIFO-based AR/R pipeline, similar to advanced AXI master examples.

3. **64-bit data width**: The default AXI data width is 64-bit. KV260 HP ports
   support up to 128-bit; changing `C_M_AXI_DATA_WIDTH = 128` would double
   peak bandwidth but requires updating the write strobe and data path widths.

4. **No cache coherency**: `ARCACHE = 4'b0010` (Normal Non-cacheable Bufferable)
   is used. For coherent access via ACP, set `ARCACHE = 4'b1111` and connect to
   the ACP port instead of HP.

5. **Buffer alignment**: `pynq.allocate()` returns physically contiguous buffers
   aligned to page boundaries. AXI burst alignment issues are avoided as long as
   burst size does not cross 4KB boundaries (which is satisfied for burst_len ≤ 16
   with 64-bit data, since 16 × 8B = 128B < 4KB).

6. **Ubuntu OS overhead**: Running under a full Linux OS (Ubuntu on PYNQ)
   introduces DDR bandwidth competition from the PS CPUs, caches, and DMA
   controllers. Practical achievable bandwidth is typically **60–85%** of the
   DDR4-2400 theoretical peak of 19.2 GB/s when measured from PL-only traffic.

---

## Reuse as Template

To adapt this design for other KV260/PYNQ PS-PL DDR experiments:

1. **Change data width**: Set `C_M_AXI_DATA_WIDTH` parameter (must match HP port width).
2. **Change number of ports**: Duplicate/remove `ddr_bw_traffic_gen` instances in `ddr_bw_top.v`
   and add corresponding base address registers in `ddr_bw_reg_ctrl.v`.
3. **Custom data patterns**: Modify `wdata_pattern` in `ddr_bw_traffic_gen.v` to
   write specific test data (e.g. all-zeros, checkerboard, LFSR).
4. **Add read-verify**: After a write run, add a read pass and compare data against
   the written pattern in software.
5. **Latency measurement**: Add a per-burst latency counter (cycles from AR to RLAST)
   to expose memory access latency alongside bandwidth.
