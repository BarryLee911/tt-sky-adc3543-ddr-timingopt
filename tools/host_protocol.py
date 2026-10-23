"""Minimal existing 3-fragment decoder and ideal-sine calibration, no I/O driver."""
import math
class Decoder:
    def __init__(self):self.reset()
    def reset(self):
        self.ready=False;self.part=0;self.snapshot=0
    def feed(self,kind,word):
        if not 0<=word<2048 or kind not in (0,1):raise ValueError('11-bit word and TYPE required')
        if kind==0:return {'count':word,'valid':self.ready}
        tag=word>>9;payload=word&511
        if tag==3:self.reset();return {'valid':False}
        if tag==0:self.snapshot=payload;self.part=1;return None
        if tag!=self.part:self.reset();return {'valid':False}
        self.snapshot|=payload<<(9*tag)
        if tag==1:self.part=2;return None
        self.part=0;self.ready=True
        return {'sum27':self.snapshot,'amplitude_old_codes':self.snapshot*math.pi/1048576,'valid':True}
def selftest():
    d=Decoder();assert not d.feed(0,500)['valid']
    for raw29 in [0,1,2,3,4,8191,8192,268435455,268435456]:
        s=raw29>>2
        assert 0<=raw29-4*s<4
        for tag in range(3):r=d.feed(1,(tag<<9)|((s>>(tag*9))&511))
        assert r['sum27']==s and r['valid']
        exact=raw29*math.pi/4194304
        assert abs(exact-r['amplitude_old_codes']) < math.pi/1048576 + 1e-12
    d.feed(1,17);d.feed(1,3<<9);assert not d.feed(0,500)['valid']
    assert not d.feed(1,2<<9)['valid']
    print('HOST_PROTOCOL_PASS,calibration_cases=9,abort_and_order_checks=3')
if __name__=='__main__':selftest()
