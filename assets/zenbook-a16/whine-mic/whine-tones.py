#!/usr/bin/env python3
# whine-tones.py file.wav f1 f2 ...: level (dBFS) of the strongest bin within +-40 Hz of each tone, plus the
# median 1-3 kHz level as a contamination check (voices / movement raise it).
import sys, wave, struct, cmath, math
def fft(x):
    n=len(x)
    if n==1: return x
    e=fft(x[0::2]); o=fft(x[1::2]); t=[cmath.exp(-2j*math.pi*k/n)*o[k] for k in range(n//2)]
    return [e[k]+t[k] for k in range(n//2)]+[e[k]-t[k] for k in range(n//2)]
w=wave.open(sys.argv[1]); sr=w.getframerate(); ch=w.getnchannels(); raw=w.readframes(w.getnframes())
s=struct.unpack('<%dh'%(len(raw)//2), raw)[::ch]; N=32768; acc=[0.0]*(N//2); cnt=0
for st in range(0, len(s)-N+1, N//2):
    seg=[s[st+i]/32768.0*(0.5-0.5*math.cos(2*math.pi*i/N)) for i in range(N)]; X=fft(seg)
    for k in range(N//2): acc[k]+=abs(X[k])**2
    cnt+=1
    if cnt>=8: break
db=[10*math.log10(acc[k]/cnt/(N*N/16)+1e-20) for k in range(N//2)]
b=lambda f:int(round(f*N/sr)); wdt=int(40*N/sr)+1
out=[]
for f in map(float, sys.argv[2:]): out.append("%dHz=%.1f" % (f, max(db[b(f)-wdt:b(f)+wdt])))
band=sorted(db[b(1000):b(3000)]); print(" ".join(out), " bb1-3k=%.1f" % band[len(band)//2])
