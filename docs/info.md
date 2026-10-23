## How it works

The design receives the ADC3543 native seven-wire parallel DDR stream on the
existing eight input pads. ADC D17 through D11 connect to ui[0] through ui[6],
and DCLK connects to ui[7]. With the default ADC mapper, DCLK high carries bits
6:0 and the following low interval carries bits 13:7 of the same sample.
The receiver waits for that complete pair before advancing measurement state.

The default input format is two's complement. The complete 14-bit word is
converted once to offset binary by XORing bit13. The rectifier uses midpoint
8192. A 2048-sample overlap counter retains the previous sign-agreement/XNOR
algorithm. Rectified magnitudes form a 25-bit period sum and 29-bit moving sum
over 16 periods. Only that final sum is divided by four to retain the previous
27-bit output format; individual input samples are never truncated to 12 bits.

LEVEL1..23 are supported. For LEVEL=L, process every 2^(L-1)th complete ADC word,
retaining the previous clk/2^L effective sample rate. The physical target remains
80MHz on clk and 40MS/s ADC sampling in every mode, requiring a shared,
phase-controlled clock source. DCLK is sampled
as a marker, not used as a second ASIC clock. Frequency matching alone does
not establish correct operation. Read [interface and timing](interface-and-timing.md)
before connecting hardware.

## How to test

After ADC initialization and stable clocks, hold rst_n low for at least four
clk edges, then present LEVEL=1..23 on uio[4:0]. LEVEL0 and LEVEL24..31 do not
start the chip. The first legal LEVEL is latched until global reset; subsequent
pad changes cannot change it. See [multi-level behavior](multilevel.md).
Release the controller's uio[0] driver before the 80000-clk handoff (1ms
at the target clock). uio[4:1] remain inputs and are unused after configuration.

DATA[7:0] is on uo[7:0], DATA[10:8] on uio[7:5], and TYPE on uio[0].
TYPE alternates every clk after handoff. TYPE=0 gives the 11-bit overlap count
(2048 saturates to 2047). TYPE=1 carries DATA[10:9] as a tag:

| Tag | DATA[8:0] |
|---|---|
| 0 | New 27-bit snapshot bits 8:0 |
| 1 | Same snapshot bits 17:9 |
| 2 | Same snapshot bits 26:18 |
| 3 | Invalid measurement window; discard incomplete frame |

Repeated DCLK markers discard the affected pair, clear both measurement windows,
and restart alignment. After an error, ignore COUNT until a fresh 0/1/2 frame
arrives after 32768 newly selected samples, i.e. 32768*2^(LEVEL-1) continuous
complete ADC words. Error detection includes words omitted by decimation.
The protocol has no sequence
number or CRC: loss of a complete pair, paired repetition, and data corruption
can be undetectable. Repeated output frames are not independent measurements.

For an ideal sine, amplitude in the previous 8-bit code units is
S27*pi/1048576. This output granularity is not ADC ENOB or impedance resolution.
The official RTL and gate-level jobs share a black-box pin test. A separate
ddr-regression job exhaustively checks reconstruction, independent integer
COUNT/sums, all 23 real divider intervals, selected-sample window and reset
recovery at LEVEL1/2/3/5, two code formats, frame atomicity, and 2025 retained-delay
source-synchronous timing scenarios. The RTL pin test uses 80MHz. Gate-level functional tests use a slow clock to
settle unit-delay models; they do not demonstrate high-speed operation. The
2025-case phase analysis reports no positive common capture margin under the
retained absolute-delay assumptions; see [working point](working-point.md).

## External hardware

An ADC3543 configured for raw 14-bit parallel DDR is required. A small SPI
controller configures it but does not forward samples. FPGA bridging is not
required. The ADC outputs are 1.8V; add correctly budgeted level translation
if the board's digital inputs use another voltage. Eight matched channels are
needed for seven data signals plus DCLK. A shared clock source must provide
the required ADC clock and phase-controlled ASIC clk.

The 6x2 SKY130 build targets 12.5ns per clk using the official template's
physical flow. Standard TinyTapeout I/O constraints do not establish the actual
ADC/translator/PCB timing budget. Assess real setup and hold margins, pad rating,
clock duty/jitter/skew, and total phase delay separately. No manufactured-chip,
board, ADC SPI or end-to-end impedance performance is claimed here.
