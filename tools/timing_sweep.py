"""80MHz retained absolute delay envelopes; expected absence of a robust aperture.

Success of this analysis script means the model was reproduced, not board signoff.
The original ns delays and guards are NOT scaled down with the clock period.
"""
from run_tests import *
import concurrent.futures, csv, itertools
def compile_timing():
    cmd=[str(IVER),'-g2012','-s','tb_timing','-o',str(HERE/'tb_timing.vvp'),str(SRC/'adc3542_rx7.v'),str(HERE/'tb_timing.v')]
    p=subprocess.run(cmd,cwd=HERE,capture_output=True,text=True)
    (OUT/'timing_compile.log').write_text(p.stdout+p.stderr,encoding='utf-8')
    save(OUT/'timing_compile.json',dict(command=cmd,exit_code=p.returncode))
    assert p.returncode==0,p.stdout+p.stderr
def sweep():
    # ADC tPD corners, aggregate data-DCLK skew, assumed output duty distortion.
    # Direct: no extra delay. Illustrative translation: total added common delay 3..5ns.
    phases=[i*.5 for i in range(25)]
    scenarios=[(env,phase,tpd,extra,skew,duty) for env,extras in [('direct',[0]),('illustrative_translation',[3,5])]
               for phase,tpd,extra,skew,duty in itertools.product(phases,[3,5,7],extras,[-1,0,1],[-2,0,2])]
    def one(s):
        env,phase,tpd,extra,skew,duty=s
        cmd=[str(VVP),str(HERE/'tb_timing.vvp'),f'+PHASE={phase}',f'+TPD={tpd}',f'+EXTRA={extra}',f'+SKEW={skew}',f'+DUTY={duty}']
        p=subprocess.run(cmd,cwd=HERE,capture_output=True,text=True)
        assert p.returncode==0 and 'TIMING_RESULT' in p.stdout,p.stdout+p.stderr
        values={k:float(v) for k,v in re.findall(r'([a-z_]+)=(-?[\d.]+)',p.stdout)}
        return dict(envelope=env,phase_ns=phase,tpd_ns=tpd,extra_ns=extra,skew_ns=skew,duty_ns=duty,**values,
            passed=values['bad']==0 and values['aperture']==0 and values['checks']>=120,
            remaining_guard_margin_ns=min(values['setup_ns']-1.5,values['hold_ns']-1.0))
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        rows=list(pool.map(one,scenarios))
    with (OUT/'timing_sweep.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    summary={}
    for env,limits in [('direct',[11.5,11.5]),('illustrative_translation',[16.5,14.5])]:
        good=[p for p in phases if all(r['passed'] for r in rows if r['envelope']==env and r['phase_ns']==p)]
        robust=[p for p in good if min(r['remaining_guard_margin_ns'] for r in rows if r['envelope']==env and r['phase_ns']==p)>0]
        summary[env]=dict(all_corner_good_grid_phases_ns=good,positive_margin_grid_phases_ns=robust,
            scenarios=sum(r['envelope']==env for r in rows),
            analytic_strict_phase_bounds_ns=limits,strict_window_width_ns=limits[1]-limits[0],
            analytic_explanation='latest launch+skew+setup+uncertainty < phase < H+earliest next launch+skew-duty-hold-uncertainty')
    # Reproduce the approved 80MHz handoff, including the zero-margin boundary.
    # A >=0 guard check at PHI=11.5 is NOT a usable positive-width phase interval.
    assert len(rows)==2025
    assert summary['direct']['all_corner_good_grid_phases_ns']==[11.5]
    assert summary['illustrative_translation']['all_corner_good_grid_phases_ns']==[]
    assert all(not s['positive_margin_grid_phases_ns'] for s in summary.values())
    save(OUT/'timing_validation.json',dict(status='NO_POSITIVE_COMMON_MARGIN_UNDER_PREVIOUS_ASSUMPTIONS',clock_period_ns=12.5,
      adc_period_ns=25,scenarios=len(rows),setup_ns=1,hold_ns=.5,uncertainty_ns=.5,
      assumed_skew_ns=[-1,1],assumed_output_duty_distortion_ns=[-2,2],summary=summary,
      limits='Retained illustrative envelope; no measured library/PCB/translator PVT, input slew, CTS, metastability or duty guarantee. Not an ADC3543 speed-limit result or physical timing closure.',
      action='Retain 80/40MHz target; obtain actual ADC3543/translator/board/ASIC corner bounds and common clock phase before interface signoff.'))
    print('TIMING_MODEL_REPRODUCED_NO_POSITIVE_MARGIN',len(rows),summary,flush=True)
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['compile','run']);a=ap.parse_args()
    (compile_timing if a.action=='compile' else sweep)()
