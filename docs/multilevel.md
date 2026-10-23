# Multiple LEVEL settings

The 80MHz ADC3543 configuration retains the complete production RTL from the
multi-level commit 51f1efa3ad4131b0efbdf73c9521231f7d528903. Its lineage extends
the LEVEL1-only DDR implementation at commit
11c630ee90fc27b1330f48f587303fb95fbd12d5. The seven-wire receiver, rectifier,
physical output pads, TYPE cadence, 80000-clk handoff and three-fragment 27-bit
protocol are retained. Only complete-word selection and its configuration are
added. Previous local folders and reference RTL are preserved.
The official physical workflow is retained; only public Pages/viewer deployment
is restricted to main so a feature-branch build cannot replace the current
published layout. GDS, precheck, gate-level tests and docs still run on branches.

## Configuration and selected samples

After reset, present LEVEL=L on uio[4:0]. The first legal L in 1..23 is latched
until the next global reset. LEVEL0 and LEVEL24..31 keep configuration invalid
and cannot start the output handoff. Release the controller's uio[0] driver
before handoff, as before. A framing error restarts the measurement and divider
without changing the latched LEVEL or restarting the TYPE/OE handoff.

The native ADC stream remains 40MS/s with a phase-controlled 80MHz ASIC
clock. Every complete ADC word is received and checked. Only each D=2^(L-1)th
word advances COUNT, the 2048-sample index and rectified accumulation. With raw
zero-based indexing after reset/reacquisition, selected indices are D-1, 2D-1,
3D-1, ... . The same full 14-bit selected sample drives sign and magnitude.
Do not divide the receiver clock or skip half-words.

The old effective rate clk/2^L is preserved for L=1..23. LEVEL0 would require a
complete 14-bit word per clk; this interface supplies only one per two clk edges.
It is explicitly rejected and is not aliased to LEVEL1 or filled by duplicates.

| LEVEL | ADC words per selected sample | Effective sample rate | 2048-point reference frequency | First 16-period window |
|---|---:|---:|---:|---:|
| 1 | 1 | 40MS/s | 19.53125kHz | 0.8192ms |
| 2 | 2 | 20MS/s | 9.765625kHz | 1.6384ms |
| 3 | 4 | 10MS/s | 4.8828125kHz | 3.2768ms |
| 5 | 16 | 2.5MS/s | 1.220703125kHz | 13.1072ms |
| 8 | 128 | 312.5kS/s | 152.587890625Hz | 104.8576ms |
| 23 | 4194304 | 9.5367431640625S/s | 0.004656612873Hz | 3435.9738368s |

For other legal levels: fs_eff=80000000/2^L, f_ref=fs_eff/2048 and
T_window=32768/fs_eff. The table gives acquisition durations, excluding initial
alignment, the declared pipeline and the next tag0 frame. The unchanged output
handoff is 1ms. Output tag3 therefore persists much longer at high LEVELs;
handoff completion does not mean a valid measurement window exists. After a
framing error, discard incomplete output frames and wait for a fresh complete
tag0/1/2 frame. COUNT is unqualified while that new window is warming up.

## Signal and timing limits

Changing LEVEL does not automatically retune an external excitation source or
the ADC. Coordinate excitation frequency and phase with the selected-sample
reference. Full-rate ADC conversion latency, initial pair alignment and the
selected word's phase still require physical calibration.

This is point decimation, with no added digital anti-alias filter. Signal/noise
above the new Nyquist limit can fold into the selected stream. Existing analog
bandwidth/filtering and the intended waveform must be assessed for the chosen
LEVEL; multiple settings alone do not establish equal measurement accuracy.
The ideal-sine output calibration factor is unchanged because every result
still sums 16*2048 selected samples before the final divide by four. The physical
time covered by that sum changes with LEVEL. Repeated frames are held results,
not independent windows.

Every setting has the same full-rate DDR pad timing requirement. Higher LEVELs
do not relax the ADC/translator/PCB sampling aperture. The original absolute-ns behavioral phase assumptions are retained: at 80MHz
they give no positive common aperture. Inspect this revision's actual physical
reports separately from functional results; the model is not board signoff.

## Reproducible validation

Use the README commands and official RTL/gate-level jobs. Added tests include:

- Configuration of all LEVEL1..23, all 9 invalid codes, reset-only selection and
  changing all 32 input codes after the latch without changing the setting.
- Real-rate DDR through two actual divider terminal events in every legal mode.
  LEVEL23 receives 8,388,608 full words; no force, deposit, shortened counter or
  near-terminal preload is used. COUNT and amplitude cannot advance on omitted
  words. This validates all divider widths, but is not a complete 57.27-minute
  LEVEL23 measurement-window simulation.
- Independent integer COUNT, block sums, 16-period sums and frame snapshots at
  LEVEL1/2/3/5; framing faults and half-word reset recovery also restart selection
  phase, including faults in words that would otherwise have been omitted.
- The official pin-only RTL/gate-level test checks LEVEL1 and LEVEL2 full windows,
  LEVEL5 selected-sample COUNT, illegal LEVEL0, reset/reconfiguration, latched
  configuration, 80000-clk handoff and unchanged output tags.
- The unchanged receiver bit-order/code-format tests, 2025-case timing model and
  preserved reference-source hashes run again.

Full-window arithmetic at the remaining levels uses the same sample-valid
datapath, but has not been exhaustively simulated for those very long intervals.
Simulation does not establish ADC ENOB, impedance resolution or physical-board
80MHz operation.
