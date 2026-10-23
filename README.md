> **时序优化版（2026-10-23）**：在提交 `19251b9` 的基础上做了三处纯时序修改（输入与复位寄存、`backend_process` 寄存、16 周期累加流水线化）。功能不变，复位释放后引脚等于原设计晚 5 个时钟。详见 `时序优化说明.md`。

# ADC3543 native DDR receiver for TinyTapeout SKY130

[![gds](https://github.com/BarryLee911/tt-sky-adc3542-ddr/actions/workflows/gds.yaml/badge.svg)](https://github.com/BarryLee911/tt-sky-adc3542-ddr/actions/workflows/gds.yaml)
[![test](https://github.com/BarryLee911/tt-sky-adc3542-ddr/actions/workflows/test.yaml/badge.svg)](https://github.com/BarryLee911/tt-sky-adc3542-ddr/actions/workflows/test.yaml)
[![ddr-regression](https://github.com/BarryLee911/tt-sky-adc3542-ddr/actions/workflows/ddr-regression.yaml/badge.svg)](https://github.com/BarryLee911/tt-sky-adc3542-ddr/actions/workflows/ddr-regression.yaml)
[![docs](https://github.com/BarryLee911/tt-sky-adc3542-ddr/actions/workflows/docs.yaml/badge.svg)](https://github.com/BarryLee911/tt-sky-adc3542-ddr/actions/workflows/docs.yaml)

Created using the official [TinyTapeout SKY130 Verilog template](https://github.com/TinyTapeout/ttsky-verilog-template).
The official GDS, precheck, gate-level test and documentation workflows are retained.
Target: **6x2 tiles, 80MHz core clock, 40MS/s ADC, LEVEL=1..23**.

Seven data pads plus DCLK reconstruct every full 14-bit ADC word inside the ASIC.
The previous COUNT algorithm and three-fragment 27-bit output protocol are retained.
The 29-bit moving sum is divided by four only after full 14-bit accumulation.
Default ADC input format is two's complement; no external FPGA data bridge is required.

LEVEL controls processing after complete-word assembly. For LEVEL=L, select every
2^(L-1)th ADC word: the effective rate is clk/2^L. The ADC stream and receiver
remain at full rate in every mode. LEVEL0 and LEVEL24..31 are rejected. See
[multi-level behavior and validation](docs/multilevel.md) before changing modes.

本仓库从官方模板创建并公开。原8位、12位原型和上一轮本地交付均保留；新仓库仅增加
多档完整样本选择及ADC3543的80MHz/40MS/s配置。生产数据通路沿用多档基线，
模块和源码名称保留。80MHz是构建目标；当前保留的绝对延迟模型没有正的共同
采样余量，实际ADC/电平转换/PCB接口尚未签核，不能用流程绿灯代替接口时序保证。

- [Approved 80/40MHz working point and limits](docs/working-point.md)
- [Machine-readable profile](config/working_point.json)
- [Project datasheet / pin protocol](docs/info.md)
- [Wiring, initialization and timing assumptions](docs/interface-and-timing.md)
- [Original local functional evidence](docs/local-validation-summary.json)
- [Template and preserved-source provenance](build_provenance.json)

## Tests

The official `test` and `gl_test` jobs run the same pin-level cocotb test, including
full-scale 27-bit output, midpoint input, TYPE/OE handoff, framing-error invalidation
and reset. RTL uses an 80MHz clock; gate-level functional simulation deliberately
uses a slow settling clock.

The additional full regression checks all 23 real divider intervals (including
two actual LEVEL23 terminal events without counter preloading), independent
full-window references at LEVEL1/2/3/5, exhaustive bit order, random/boundary codes,
both code formats, independent integer COUNT and sums, frame atomicity, recovery,
and 2025 source-synchronous timing-model combinations. A reviewable artificial
stimulus generator recreates byte-identical prior clean and combined-interference
codes, checked against hashes in test/fixtures/manifest.json. No opaque fixture
archives or measured participant data are published. These are arithmetic tests, not
new ADC noise, physiological-time or human impedance performance measurements.

With Python 3.12+ and Icarus installed:

```
pip install -r tools/requirements.txt
python tools/run_tests.py prepare
python tools/run_tests.py compile
python tools/run_tests.py run
python tools/timing_sweep.py compile
python tools/timing_sweep.py run
python tools/host_protocol.py
```

For the official cocotb harness, install test/requirements.txt, then run `make` in
test/ and verify results.xml with `python -m cocotb_tools.check_results results.xml`.
New logs/reports live in ignored build/ and GitHub Actions artifacts. No original
workspace paths, credentials, paper sources, vendor PDFs or raw study data are needed.

The phase-model script succeeds when it reproduces the expected unclosed aperture;
its report status is NO_POSITIVE_COMMON_MARGIN_UNDER_PREVIOUS_ASSUMPTIONS.
A green regression job therefore does not mean the external interface timing passes.

The ASIC flow uses the official template's standard I/O assumptions; even a successful
GDS build does not sign off the external ADC DDR aperture. Read timing reports and
the documented physical limitations before making any high-speed hardware claim.
