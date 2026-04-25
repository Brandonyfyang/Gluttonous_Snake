"""
DDR Bandwidth Benchmark - PYNQ Python Driver

Provides the DDRBandwidthBenchmark class for controlling the ddr_bw_top
hardware overlay from the PS side on KV260 (or any PYNQ-compatible Zynq board).

Usage example:
    from ddr_bw_benchmark import DDRBandwidthBenchmark, BenchmarkConfig
    from ddr_bw_regs import MODE_READ, MODE_WRITE, MODE_RD_WR_SPLIT

    cfg = BenchmarkConfig(
        mode=MODE_READ,
        burst_len=16,
        total_bursts=4096,
        buf_size_bytes=4 * 1024 * 1024,  # 4 MB per port
    )

    bm = DDRBandwidthBenchmark('ddr_bw.bit')
    bm.load()
    results = bm.run(cfg)
    bm.print_results(results)
    bm.close()

Architecture notes:
    - The overlay exposes a single AXI-Lite IP block named 'ddr_bw_top_0'.
    - Four contiguous pynq.allocate() buffers are used, one per port.
    - The hardware writes/reads these buffers directly via AXI HP ports.
    - Wall-clock time is measured with time.perf_counter() for software BW.
    - Hardware cycle count (from CYCLE_CNT registers) gives hardware BW.
"""

import time
import numpy as np

try:
    import pynq
    from pynq import Overlay, allocate
    _PYNQ_AVAILABLE = True
except ImportError:
    _PYNQ_AVAILABLE = False

from ddr_bw_regs import (
    REG_CTRL, REG_STATUS, REG_BURST_LEN, REG_TOTAL_BURSTS,
    REG_P0_BASE_LOW, REG_P0_BASE_HIGH,
    REG_P1_BASE_LOW, REG_P1_BASE_HIGH,
    REG_P2_BASE_LOW, REG_P2_BASE_HIGH,
    REG_P3_BASE_LOW, REG_P3_BASE_HIGH,
    REG_CYCLE_CNT_L, REG_CYCLE_CNT_H,
    REG_P0_BEAT_CNT, REG_P1_BEAT_CNT, REG_P2_BEAT_CNT, REG_P3_BEAT_CNT,
    REG_P0_BURST_CNT, REG_P1_BURST_CNT, REG_P2_BURST_CNT, REG_P3_BURST_CNT,
    CTRL_START, CTRL_STOP, CTRL_SW_RESET, CTRL_MODE_SHIFT,
    STATUS_ALL_DONE, STATUS_ANY_ERROR,
    STATUS_PORT_DONE_SHIFT, STATUS_PORT_DONE_MASK,
    STATUS_PORT_ACTIVE_SHIFT, STATUS_PORT_ACTIVE_MASK,
    MODE_READ, MODE_WRITE, MODE_RD_WR_SPLIT, MODE_NAMES,
    DEFAULT_BURST_LEN, DEFAULT_TOTAL_BURSTS, AXI_DATA_WIDTH_BYTES,
    bytes_per_port,
)


# ---------------------------------------------------------------------------
# Data classes (simple named tuples / dicts for broad Python compatibility)
# ---------------------------------------------------------------------------

class BenchmarkConfig:
    """Configuration for a single benchmark run."""

    def __init__(
        self,
        mode: int = MODE_READ,
        burst_len: int = DEFAULT_BURST_LEN,
        total_bursts: int = DEFAULT_TOTAL_BURSTS,
        buf_size_bytes: int = 4 * 1024 * 1024,
        clk_freq_mhz: float = 300.0,
        ip_name: str = "ddr_bw_top_0",
        timeout_s: float = 10.0,
    ):
        """
        Parameters
        ----------
        mode : int
            Transfer mode: MODE_READ (0), MODE_WRITE (1), or MODE_RD_WR_SPLIT (2).
        burst_len : int
            AXI burst length in beats (1-255). Default 16.
        total_bursts : int
            Total number of bursts issued per port (1-65535). Default 256.
        buf_size_bytes : int
            Size in bytes of each per-port DDR buffer. Should be large enough
            to hold burst_len * total_bursts * AXI_DATA_WIDTH_BYTES bytes.
            Default 4 MB.
        clk_freq_mhz : float
            PL clock frequency in MHz, used for hardware bandwidth calculation.
            KV260 default is 300 MHz (pl_clk0). Override if you use a different
            frequency.
        ip_name : str
            Name of the IP block in the overlay (as reported by overlay.ip_dict).
        timeout_s : float
            Timeout in seconds when polling for completion. Default 10 s.
        """
        if burst_len < 1 or burst_len > 255:
            raise ValueError(f"burst_len must be 1-255, got {burst_len}")
        if total_bursts < 1 or total_bursts > 65535:
            raise ValueError(f"total_bursts must be 1-65535, got {total_bursts}")
        if mode not in MODE_NAMES:
            raise ValueError(f"mode must be one of {list(MODE_NAMES.keys())}, got {mode}")

        self.mode = mode
        self.burst_len = burst_len
        self.total_bursts = total_bursts
        self.buf_size_bytes = buf_size_bytes
        self.clk_freq_mhz = clk_freq_mhz
        self.ip_name = ip_name
        self.timeout_s = timeout_s

    @property
    def bytes_per_burst(self) -> int:
        return self.burst_len * AXI_DATA_WIDTH_BYTES

    @property
    def total_bytes_per_port(self) -> int:
        return self.total_bursts * self.bytes_per_burst

    def __repr__(self):
        return (
            f"BenchmarkConfig(mode={MODE_NAMES[self.mode]}, "
            f"burst_len={self.burst_len}, total_bursts={self.total_bursts}, "
            f"buf_size_bytes={self.buf_size_bytes}, clk_freq_mhz={self.clk_freq_mhz})"
        )


class BenchmarkResults:
    """Results from a single benchmark run."""

    def __init__(
        self,
        config: BenchmarkConfig,
        wall_time_s: float,
        hw_cycles: int,
        port_beat_counts: list,
        port_burst_counts: list,
        status: int,
    ):
        self.config = config
        self.wall_time_s = wall_time_s
        self.hw_cycles = hw_cycles
        self.port_beat_counts = port_beat_counts    # list of 4 ints
        self.port_burst_counts = port_burst_counts  # list of 4 ints
        self.status = status

    # ---- Derived metrics --------------------------------------------------

    @property
    def hw_time_s(self) -> float:
        """Hardware elapsed time in seconds (from cycle counter)."""
        if self.config.clk_freq_mhz <= 0:
            return 0.0
        return self.hw_cycles / (self.config.clk_freq_mhz * 1e6)

    @property
    def total_bytes_transferred(self) -> int:
        """Total bytes transferred across all ports."""
        return sum(bytes_per_port(bc) for bc in self.port_beat_counts)

    @property
    def sw_aggregate_bw_gbps(self) -> float:
        """Software-side aggregate bandwidth in GB/s (wall-clock time)."""
        if self.wall_time_s <= 0:
            return 0.0
        return self.total_bytes_transferred / self.wall_time_s / 1e9

    @property
    def hw_aggregate_bw_gbps(self) -> float:
        """Hardware-side aggregate bandwidth in GB/s (cycle counter time)."""
        t = self.hw_time_s
        if t <= 0:
            return 0.0
        return self.total_bytes_transferred / t / 1e9

    def port_sw_bw_gbps(self, port: int) -> float:
        """Per-port software-side bandwidth in GB/s."""
        if self.wall_time_s <= 0:
            return 0.0
        return bytes_per_port(self.port_beat_counts[port]) / self.wall_time_s / 1e9

    def port_hw_bw_gbps(self, port: int) -> float:
        """Per-port hardware-side bandwidth in GB/s."""
        t = self.hw_time_s
        if t <= 0:
            return 0.0
        return bytes_per_port(self.port_beat_counts[port]) / t / 1e9

    @property
    def all_done(self) -> bool:
        return bool(self.status & STATUS_ALL_DONE)

    @property
    def any_error(self) -> bool:
        return bool(self.status & STATUS_ANY_ERROR)

    def __repr__(self):
        return (
            f"BenchmarkResults(hw_agg={self.hw_aggregate_bw_gbps:.3f} GB/s, "
            f"sw_agg={self.sw_aggregate_bw_gbps:.3f} GB/s, "
            f"hw_cycles={self.hw_cycles}, wall={self.wall_time_s:.4f}s, "
            f"all_done={self.all_done}, error={self.any_error})"
        )


# ---------------------------------------------------------------------------
# Main driver class
# ---------------------------------------------------------------------------

class DDRBandwidthBenchmark:
    """
    PYNQ-based driver for the ddr_bw_top hardware overlay.

    Controls the 4-port AXI Master DDR bandwidth benchmark engine via the
    AXI-Lite register interface, allocates DDR buffers, and collects results.

    Example
    -------
    >>> bm = DDRBandwidthBenchmark('ddr_bw.bit')
    >>> bm.load()
    >>> cfg = BenchmarkConfig(mode=MODE_READ, burst_len=16, total_bursts=4096)
    >>> results = bm.run(cfg)
    >>> bm.print_results(results)
    >>> bm.close()
    """

    NUM_PORTS = 4

    def __init__(self, bitfile_path: str):
        """
        Parameters
        ----------
        bitfile_path : str
            Path to the .bit bitstream file.  The corresponding .hwh file
            must exist in the same directory.
        """
        self.bitfile_path = bitfile_path
        self.overlay = None
        self._ip = None
        self._buffers = [None] * self.NUM_PORTS

    # ---- Overlay management -----------------------------------------------

    def load(self):
        """Load the bitstream onto the PL and obtain the IP register handle."""
        if not _PYNQ_AVAILABLE:
            raise RuntimeError(
                "pynq package is not available. "
                "Install it with: pip install pynq"
            )
        print(f"Loading overlay: {self.bitfile_path} ...")
        self.overlay = Overlay(self.bitfile_path)
        print("Overlay loaded successfully.")

    def _get_ip(self, ip_name: str):
        """Return the MMIO / register handle for the given IP block."""
        if self.overlay is None:
            raise RuntimeError("Overlay not loaded. Call load() first.")
        if ip_name not in self.overlay.ip_dict:
            available = list(self.overlay.ip_dict.keys())
            raise ValueError(
                f"IP '{ip_name}' not found in overlay. "
                f"Available IPs: {available}"
            )
        return getattr(self.overlay, ip_name)

    # ---- Register access --------------------------------------------------

    def _write_reg(self, ip, offset: int, value: int):
        """Write a 32-bit value to the given register offset."""
        ip.write(offset, value & 0xFFFFFFFF)

    def _read_reg(self, ip, offset: int) -> int:
        """Read a 32-bit value from the given register offset."""
        return ip.read(offset) & 0xFFFFFFFF

    # ---- Buffer management ------------------------------------------------

    def _alloc_buffers(self, buf_size_bytes: int):
        """Allocate 4 contiguous DDR buffers (one per port) via pynq.allocate."""
        print(f"Allocating 4 × {buf_size_bytes // 1024} KB DDR buffers ...")
        for i in range(self.NUM_PORTS):
            if self._buffers[i] is not None:
                self._buffers[i].freebuffer()
            self._buffers[i] = allocate(shape=(buf_size_bytes,), dtype=np.uint8)
            # Initialize with a pattern so reads have valid data
            self._buffers[i][:] = np.arange(buf_size_bytes, dtype=np.uint8)
            self._buffers[i].flush()
        print("Buffers allocated and initialized.")

    def _free_buffers(self):
        """Free all allocated DDR buffers."""
        for i in range(self.NUM_PORTS):
            if self._buffers[i] is not None:
                self._buffers[i].freebuffer()
                self._buffers[i] = None

    def _get_phys_addr(self, buf) -> int:
        """Return the physical (device) address of a pynq.allocate buffer."""
        return buf.device_address

    # ---- Configuration ----------------------------------------------------

    def configure(self, ip, cfg: BenchmarkConfig):
        """
        Write all configuration registers before starting a run.

        Parameters
        ----------
        ip
            IP register handle obtained from the overlay.
        cfg : BenchmarkConfig
            Benchmark configuration to apply.
        """
        # Software reset to clear previous run state
        self._write_reg(ip, REG_CTRL, CTRL_SW_RESET)
        time.sleep(0.001)
        self._write_reg(ip, REG_CTRL, 0)  # deassert reset

        # Set burst length and total bursts
        self._write_reg(ip, REG_BURST_LEN,    cfg.burst_len & 0xFF)
        self._write_reg(ip, REG_TOTAL_BURSTS, cfg.total_bursts & 0xFFFF)

        # Set per-port base addresses from allocated buffers
        base_regs = [
            (REG_P0_BASE_LOW, REG_P0_BASE_HIGH),
            (REG_P1_BASE_LOW, REG_P1_BASE_HIGH),
            (REG_P2_BASE_LOW, REG_P2_BASE_HIGH),
            (REG_P3_BASE_LOW, REG_P3_BASE_HIGH),
        ]
        for i, (low_reg, high_reg) in enumerate(base_regs):
            phys = self._get_phys_addr(self._buffers[i])
            self._write_reg(ip, low_reg,  phys & 0xFFFFFFFF)
            self._write_reg(ip, high_reg, (phys >> 32) & 0xFFFFFFFF)

        # Mode is embedded in CTRL[5:4] - write along with mode bits (no start yet)
        ctrl_val = (cfg.mode & 0x3) << CTRL_MODE_SHIFT
        self._write_reg(ip, REG_CTRL, ctrl_val)

    # ---- Run control ------------------------------------------------------

    def start(self, ip, cfg: BenchmarkConfig):
        """
        Trigger the benchmark start (sets CTRL[0]=1, hardware self-clears it).
        Returns the wall-clock time just before start.
        """
        # Preserve mode bits, set start bit
        ctrl_val = ((cfg.mode & 0x3) << CTRL_MODE_SHIFT) | CTRL_START
        t0 = time.perf_counter()
        self._write_reg(ip, REG_CTRL, ctrl_val)
        return t0

    def wait_done(self, ip, timeout_s: float = 10.0) -> float:
        """
        Poll STATUS register until all_done is set or timeout.

        Returns
        -------
        float
            Wall-clock elapsed time in seconds from call to return.
        """
        t0 = time.perf_counter()
        deadline = t0 + timeout_s
        while time.perf_counter() < deadline:
            status = self._read_reg(ip, REG_STATUS)
            if status & STATUS_ALL_DONE:
                return time.perf_counter() - t0
            time.sleep(0.0001)
        # Timeout: return elapsed without all_done
        return time.perf_counter() - t0

    def stop(self, ip):
        """Request an early stop (sets CTRL[1]=1)."""
        status = self._read_reg(ip, REG_CTRL)
        self._write_reg(ip, REG_CTRL, status | CTRL_STOP)

    # ---- Results readback -------------------------------------------------

    def read_results(self, ip, cfg: BenchmarkConfig, wall_time_s: float) -> BenchmarkResults:
        """
        Read all result registers and construct a BenchmarkResults object.

        Parameters
        ----------
        ip
            IP register handle.
        cfg : BenchmarkConfig
            The configuration used for this run.
        wall_time_s : float
            Elapsed wall-clock time from start to done (measured externally).

        Returns
        -------
        BenchmarkResults
        """
        status      = self._read_reg(ip, REG_STATUS)
        cycle_low   = self._read_reg(ip, REG_CYCLE_CNT_L)
        cycle_high  = self._read_reg(ip, REG_CYCLE_CNT_H)
        hw_cycles   = (cycle_high << 32) | cycle_low

        beat_counts  = [
            self._read_reg(ip, REG_P0_BEAT_CNT),
            self._read_reg(ip, REG_P1_BEAT_CNT),
            self._read_reg(ip, REG_P2_BEAT_CNT),
            self._read_reg(ip, REG_P3_BEAT_CNT),
        ]
        burst_counts = [
            self._read_reg(ip, REG_P0_BURST_CNT),
            self._read_reg(ip, REG_P1_BURST_CNT),
            self._read_reg(ip, REG_P2_BURST_CNT),
            self._read_reg(ip, REG_P3_BURST_CNT),
        ]

        return BenchmarkResults(
            config=cfg,
            wall_time_s=wall_time_s,
            hw_cycles=hw_cycles,
            port_beat_counts=beat_counts,
            port_burst_counts=burst_counts,
            status=status,
        )

    # ---- High-level run ---------------------------------------------------

    def run(self, cfg: BenchmarkConfig) -> BenchmarkResults:
        """
        Allocate buffers, configure hardware, run benchmark, and return results.

        This is the primary entry point for a full benchmark run.

        Parameters
        ----------
        cfg : BenchmarkConfig
            Benchmark configuration.

        Returns
        -------
        BenchmarkResults
        """
        ip = self._get_ip(cfg.ip_name)

        # Ensure buffers are large enough for the configured transfer size
        min_buf = cfg.total_bytes_per_port
        if cfg.buf_size_bytes < min_buf:
            print(
                f"Warning: buf_size_bytes ({cfg.buf_size_bytes}) is smaller than "
                f"total transfer per port ({min_buf}). Enlarging buffer."
            )
            cfg.buf_size_bytes = min_buf

        self._alloc_buffers(cfg.buf_size_bytes)
        self.configure(ip, cfg)

        print(
            f"Starting benchmark: mode={MODE_NAMES[cfg.mode]}, "
            f"burst_len={cfg.burst_len}, total_bursts={cfg.total_bursts}, "
            f"~{cfg.total_bytes_per_port / 1024 / 1024:.1f} MB/port ..."
        )

        t0 = self.start(ip, cfg)
        wall_time = self.wait_done(ip, timeout_s=cfg.timeout_s)

        results = self.read_results(ip, cfg, wall_time)

        if not results.all_done:
            print("Warning: benchmark timed out before all ports completed.")
        if results.any_error:
            print("Warning: AXI error(s) detected during benchmark.")

        return results

    # ---- Output -----------------------------------------------------------

    @staticmethod
    def print_results(results: BenchmarkResults):
        """Print a formatted results summary to stdout."""
        cfg = results.config
        print()
        print("=" * 60)
        print("  DDR Bandwidth Benchmark Results")
        print("=" * 60)
        print(f"  Mode           : {MODE_NAMES[cfg.mode]}")
        print(f"  Burst length   : {cfg.burst_len} beats")
        print(f"  Total bursts   : {cfg.total_bursts} per port")
        print(f"  Bytes/port     : {cfg.total_bytes_per_port / 1024 / 1024:.2f} MB")
        print(f"  PL clock       : {cfg.clk_freq_mhz:.1f} MHz")
        print()
        print(f"  Status         : {'OK' if results.all_done else 'TIMEOUT'}"
              f"{' | ERROR' if results.any_error else ''}")
        print(f"  HW cycles      : {results.hw_cycles:,}")
        print(f"  HW elapsed     : {results.hw_time_s * 1000:.3f} ms")
        print(f"  Wall elapsed   : {results.wall_time_s * 1000:.3f} ms")
        print()
        print(f"  {'Port':<6} {'Beats':>10} {'Bursts':>10} "
              f"{'Bytes':>12} {'HW BW':>10} {'SW BW':>10}")
        print(f"  {'-'*6} {'-'*10} {'-'*10} {'-'*12} {'-'*10} {'-'*10}")
        for p in range(4):
            bc   = results.port_beat_counts[p]
            brc  = results.port_burst_counts[p]
            byt  = bytes_per_port(bc)
            hwbw = results.port_hw_bw_gbps(p)
            swbw = results.port_sw_bw_gbps(p)
            print(f"  {p:<6} {bc:>10,} {brc:>10,} {byt:>12,} "
                  f"{hwbw:>9.3f}G {swbw:>9.3f}G")
        print()
        total_bytes = results.total_bytes_transferred
        print(f"  Total bytes    : {total_bytes / 1024 / 1024:.2f} MB")
        print(f"  HW agg BW      : {results.hw_aggregate_bw_gbps:.3f} GB/s")
        print(f"  SW agg BW      : {results.sw_aggregate_bw_gbps:.3f} GB/s")
        print("=" * 60)
        print()

    # ---- Cleanup ----------------------------------------------------------

    def close(self):
        """Free DDR buffers and release overlay resources."""
        self._free_buffers()
        if self.overlay is not None:
            # pynq.Overlay does not have an explicit close(), but we clear the ref
            self.overlay = None
        self._ip = None
        print("DDRBandwidthBenchmark closed.")

    def __enter__(self):
        self.load()
        return self

    def __exit__(self, *args):
        self.close()


# ---------------------------------------------------------------------------
# Standalone CLI demo (runs when executed as a script)
# ---------------------------------------------------------------------------

def _cli_demo():
    """
    Simple command-line demo that prints the register map and simulates
    a results summary without requiring actual hardware.
    """
    from ddr_bw_regs import print_register_map

    print("DDR Bandwidth Benchmark - Register Map")
    print()
    print_register_map()
    print()

    # Simulate a result for documentation / testing purposes
    cfg = BenchmarkConfig(
        mode=MODE_READ,
        burst_len=16,
        total_bursts=4096,
        clk_freq_mhz=300.0,
    )
    # Example: 300 MHz clock, 16 beats/burst, 4096 bursts per port, 4 ports
    # theoretical = 4 × 4096 × 16 × 8B / (300e6 × time) ≈ 6.4 GB/s at 100%
    simulated_cycles = 1_000_000  # ~3.3 ms at 300 MHz
    simulated_beats  = [cfg.total_bursts * cfg.burst_len] * 4  # perfect transfer
    simulated_bursts = [cfg.total_bursts] * 4

    from ddr_bw_regs import STATUS_ALL_DONE
    results = BenchmarkResults(
        config=cfg,
        wall_time_s=simulated_cycles / (cfg.clk_freq_mhz * 1e6) + 0.0005,
        hw_cycles=simulated_cycles,
        port_beat_counts=simulated_beats,
        port_burst_counts=simulated_bursts,
        status=STATUS_ALL_DONE,
    )
    DDRBandwidthBenchmark.print_results(results)


if __name__ == "__main__":
    _cli_demo()
