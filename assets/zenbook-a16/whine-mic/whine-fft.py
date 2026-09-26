#!/usr/bin/env python3
# whine-fft.py <file.wav>: pure-Python spectrum of a mono/stereo 16-bit WAV. Prints the strongest narrow peaks
# above 1 kHz (coil whine candidates) in dBFS, and the median noise floor around them.
import sys, wave, struct, cmath, math
def fft(x):
    n=len(x)
    if n==1: return x
    e=fft(x[0::2]); o=fft(x[1::2])
    t=[cmath.exp(-2j*math.pi*k/n)*o[k] for k in range(n//2)]
    return [e[k]+t[k] for k in range(n//2)]+[e[k]-t[k] for k in range(n//2)]
w=wave.open(sys.argv[1]); sr=w.getframerate(); ch=w.getnchannels(); n=w.getnframes()
raw=w.readframes(n); s=struct.unpack('<%dh'%(len(raw)//2), raw)[::ch]
N=65536
best=None
# average power spectrum over consecutive windows
acc=[0.0]*(N//2); cnt=0
for start in range(0, len(s)-N+1, N):
    seg=[s[start+i]/32768.0*(0.5-0.5*math.cos(2*math.pi*i/N)) for i in range(N)]
    X=fft(seg)
    for k in range(N//2): acc[k]+=abs(X[k])**2
    cnt+=1
    if cnt>=3: break
if cnt==0: sys.exit("clip too short")
db=[10*math.log10(acc[k]/cnt/(N*N/16)+1e-20) for k in range(N//2)]
hz=lambda k: k*sr/N
# noise floor: median in 1-20 kHz
band=[db[k] for k in range(N//2) if 1000<=hz(k)<=min(20000,sr/2-100)]
band_sorted=sorted(band); floor=band_sorted[len(band)//2]
print("sr=%d Hz  bins=%.2f Hz  noise floor (median 1-20k) = %.1f dBFS" % (sr, sr/N, floor))
# peaks: local maxima above floor+12 dB, at least 1 kHz apart, above 1 kHz
peaks=[]
for k in range(2, N//2-2):
    f=hz(k)
    if f<1000 or f>sr/2-100: continue
    if db[k]>db[k-1] and db[k]>=db[k+1] and db[k]>db[k-2] and db[k]>db[k+2] and db[k]>floor+12:
        peaks.append((db[k],f))
peaks.sort(reverse=True)
out=[]
for d,f in peaks:
    if all(abs(f-g)>300 for _,g in out): out.append((d,f))
    if len(out)>=8: break
for d,f in out: print("  peak %7.0f Hz  %6.1f dBFS  (+%.1f dB over floor)" % (f,d,d-floor))
if not out: print("  no narrow peaks above floor+12 dB")
