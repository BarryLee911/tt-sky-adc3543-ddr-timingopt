"""Entirely artificial sine/envelope/noise test codes; no participant measurements.

Formula and seeds are copied from the prior synthetic RTL experiment. Generated
samples are checked against its preserved SHA256 values before simulation.
"""
import numpy as np
N=2048
FS=312500.
FC=FS/N
WARM=4*N

def generate(c):
    n=c['n']
    idx=np.arange(n)
    theta=2*np.pi*(idx+.5)/N+(180-37.5)*np.pi/180
    tt=(idx-WARM)/FS
    fm=FC/c['carrier_periods_per_modulation']
    mod=c['mod_pp']/2*np.sin(2*np.pi*fm*np.maximum(tt,0))
    duration=(n-WARM)/FS
    drift=c['drift_pp']*(np.maximum(tt,0)/duration-.5)
    clean=c['background']+mod
    target=clean+drift
    noise=np.random.default_rng(c['seed']).normal(0,c['noise'],n) if c['noise'] else 0.
    analog=128+c['offset']+target*np.sin(theta)+noise
    return np.clip(np.floor(64*analog+.5),0,16383).astype(np.uint16)
