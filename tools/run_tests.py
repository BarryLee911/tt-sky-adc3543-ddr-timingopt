"""Reproducible functional regression; portable standalone TinyTapeout repository regression."""
from pathlib import Path
import argparse, array, hashlib, json, os, random, re, shutil, subprocess, sys, time
ROOT=Path(__file__).resolve().parents[1]
HERE=ROOT/'test/ddr'
SRC=ROOT/'src'
OUT=ROOT/'build/reports'
OUT.mkdir(parents=True,exist_ok=True)
IVER=Path(os.environ.get('IVERILOG') or shutil.which('iverilog') or 'C:/iverilog/bin/iverilog.exe')
VVP=Path(os.environ.get('VVP') or shutil.which('vvp') or 'C:/iverilog/bin/vvp.exe')
OLD=ROOT/'test/reference/project_12bit.v'
PROTECTED={
 'test/reference/project_8bit.v':'279db397eecc4afd91e2f172e8bf21a465506f964cbf1438a8e865b14531323e',
 'test/reference/project_12bit.v':'c29208d0cec6146be16f8769a1fccd7e21cd5fefef325d550656d8d3f7501102',
 'src/meanabs_candidate.v':'41db477363224763b4ed180d3de584f9fff50554051286889c100f782c0ad21f',
 # Reference build (commit 19251b9 src/project_adc3542_ddr.v) with only its module renamed to _orig.
 'test/reference/project_adc3542_ddr_orig.v':'a60e365e43b747d664800e80f42248474621a61178f0df00265b386dc71b405f'}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding='utf-8')
def integrity():
    result={p:dict(expected=h,actual=sha(ROOT/p)) for p,h in PROTECTED.items()}
    assert all(v['actual']==v['expected'] for v in result.values())
    assert sha(SRC/'meanabs_candidate.v')==PROTECTED['src/meanabs_candidate.v']
    save(OUT/'protected_hashes.json',result)
    return result
def prepare():
    OUT.mkdir(exist_ok=True);integrity()
    folder=OUT/'stimuli';folder.mkdir(exist_ok=True)
    rng=random.Random(20261022)
    random_codes=[0,8191,8192,16383,127,16256,0x1555,0x2aaa]+[rng.randrange(16384) for _ in range(262144-8)]
    cases=[]
    for name,values in [('random',random_codes),('zero',[0]*65536),('maximum',[16383]*65536),('midpoint',[8192]*65536)]:
        p=folder/f'{name}.bin';a=array.array('H',values)
        if sys.byteorder!='little':a.byteswap()
        p.write_bytes(a.tobytes());cases.append(dict(name=name,input=str(p),n=len(values),faults=0))
    # Regenerate exact prior artificial codes from reviewable formulas and seeds.
    from synthetic_stimulus import generate
    fixtures=json.loads((ROOT/'test/fixtures/manifest.json').read_text(encoding='utf-8'))
    for fixture in fixtures:
        p=folder/f"{fixture['name']}.bin"
        start=fixture['case_sample_offset']
        values=generate(fixture['parameters'])[start:start+fixture['n']]
        p.write_bytes(values.astype('<u2').tobytes())
        assert sha(p)==fixture['sha256']
        cases.append(dict(name=fixture['name'],input=str(p),n=fixture['n'],faults=0,fixture=fixture))
    cases.append(dict(name='faults',input=str(folder/'random.bin'),n=262144,faults=1))
    for c in cases:c['sha256']=sha(c['input'])
    save(OUT/'jobs.json',cases)
    # Independent full-window regressions for decimated streams. No archived data.
    p=folder/'levels_random.bin';a=array.array('H',(rng.randrange(16384) for _ in range(655360)))
    if sys.byteorder!='little':a.byteswap()
    p.write_bytes(a.tobytes())
    save(OUT/'level_jobs.json',[
        dict(name='level2_faults',exe='tb_stream_level2',n=655360,faults=1),
        dict(name='level3_offset_faults',exe='tb_stream_level3',n=655360,faults=1),
        dict(name='level5_window',exe='tb_stream_level5',n=655360,faults=0)])
    print('PREPARE_PASS',flush=True)
def compile_all():
    integrity();records=[]
    common=[str(SRC/p) for p in ['adc3542_rx7.v','meanabs_candidate.v','meanabs_pipelined.v','project_adc3542_ddr.v']]
    common+=[str(ROOT/'test/reference/project_adc3542_ddr_orig.v'),str(HERE/'pin_equiv.v')]
    for top,opts in [('tb_rx',[]),('tb_config',[]),('tb_levels',[]),('tb_stream',[]),('tb_stream_short',['-Ptb_stream.HANDOFF=17']),('tb_stream_offset',['-Ptb_stream.TWOS=0']),
                     ('tb_stream_level2',['-Ptb_stream.LEVEL=2']),
                     ('tb_stream_level3',['-Ptb_stream.LEVEL=3','-Ptb_stream.TWOS=0']),
                     ('tb_stream_level5',['-Ptb_stream.LEVEL=5'])]:
        actual='tb_stream' if top.startswith('tb_stream') else top
        cmd=[str(IVER),'-g2012','-Wall','-s',actual,*opts,'-o',str(HERE/f'{top}.vvp'),*common,str(OLD),str(HERE/f'{actual}.v')]
        p=subprocess.run(cmd,cwd=HERE,capture_output=True,text=True)
        (OUT/f'{top}_compile.log').write_text(p.stdout+p.stderr,encoding='utf-8')
        records.append(dict(command=cmd,exit_code=p.returncode))
        if p.returncode:
            save(OUT/'compile.json',records);raise RuntimeError(f'Compile failed {p.returncode}; see {top}_compile.log')
    save(OUT/'compile.json',records);print('COMPILE_PASS',flush=True)
def run_one(name,exe,args,marker):
    cmd=[str(VVP),str(HERE/f'{exe}.vvp'),*args];start=time.monotonic()
    p=subprocess.run(cmd,cwd=HERE,capture_output=True,text=True)
    log=p.stdout+p.stderr;(OUT/f'{name}.log').write_text(log,encoding='utf-8')
    assert p.returncode==0 and marker in log,log
    print(name,log.strip(),flush=True)
    return dict(name=name,command=cmd,seconds=time.monotonic()-start,status='PASS',counts={k:int(v) for k,v in re.findall(r'([a-z_0-9]+)=(\d+)',log)})
def run_all():
    integrity();records=[run_one('receiver','tb_rx',[],'RX_PASS'),run_one('configuration','tb_config',[],'CONFIG_PASS')]
    cases=json.loads((OUT/'jobs.json').read_text(encoding='utf-8'))
    for c in cases:
        assert sha(c['input'])==c['sha256']
        args=[f'+INPUT={Path(c["input"]).as_posix()}',f'+N={c["n"]}',f'+FAULTS={c["faults"]}']
        records.append(run_one(c['name'],'tb_stream',args,'STREAM_PASS'))
    c=cases[0];args=[f'+INPUT={Path(c["input"]).as_posix()}',f'+N={c["n"]}']
    records.append(run_one('early_handoff_faults','tb_stream_short',[*args,'+FAULTS=1'],'STREAM_PASS'))
    records.append(run_one('offset_binary','tb_stream_offset',args,'STREAM_PASS'))
    for c in json.loads((OUT/'level_jobs.json').read_text(encoding='utf-8')):
        args=[f'+INPUT={(OUT/"stimuli/levels_random.bin").as_posix()}',f'+N={c["n"]}',f'+FAULTS={c["faults"]}']
        records.append(run_one(c['name'],c['exe'],args,'STREAM_PASS'))
    records.append(run_one('all_level_real_intervals','tb_levels',[],'LEVELS_PASS'))
    total={k:sum(r['counts'].get(k,0) for r in records) for k in ['samples','accepted','count_checks','frames','invalids','updates_open','errors','resets','equiv_checks','equiv_reset_checks']}
    assert all(r['counts'].get('equiv_checks',0)>0 for r in records if r['name']!='receiver')
    streams=[r['counts'] for r in records if 'frames' in r['counts']]
    assert max(r['max_sum16'] for r in streams)==268435456
    assert any(r['updates_open']>0 for r in streams)
    assert any(r['remainder_mask']==15 for r in streams)
    save(OUT/'functional_validation.json',dict(status='PASS',master_clock_hz=80000000,adc_samples_per_second=40000000,runs=records,total=total,protected=integrity(),scope='80MHz RTL source schedule; reference build checked by the original oracle, optimized build checked pin-for-pin against it with a fixed 5-cycle latency; no physical timing/ENOB/performance guarantee'))
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['prepare','compile','run','integrity']);a=ap.parse_args()
    {'prepare':prepare,'compile':compile_all,'run':run_all,'integrity':integrity}[a.action]()
