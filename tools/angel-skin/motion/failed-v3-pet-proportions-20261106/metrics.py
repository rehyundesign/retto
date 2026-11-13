"""Companion facial cross-section measurements, independent of ears/arms/bows."""
import numpy as np
from prepare import old
def bbox(c):
    ys=[y for y,x in c];xs=[x for y,x in c];return [min(xs),min(ys),max(xs)+1,max(ys)+1]
def centre(c):return [float(np.mean([x for y,x in c])),float(np.mean([y for y,x in c]))]
def measure(im):
    a=np.asarray(im).astype(int);r,g,b,alpha=[a[:,:,k] for k in range(4)];yy,xx=np.indices(alpha.shape)
    bell=old.landmarks(im,0)['tato_bell']
    result={}
    masks={'Tato':(r<75)&(g<75)&(b<80)&(alpha>200)&(abs(xx-bell[0])<40)&(yy>bell[1]-80)&(yy<bell[1]-25),
           'Melody':(r>80)&(g<95)&(b<125)&(r>g*2)&(r>b*1.3)&(alpha>200)&(xx>330)&(yy>90)&(yy<285)}
    for name,mask in masks.items():
        cs=[]
        for c in old.comps(mask,6):
            q=bbox(c);w=q[2]-q[0];h=q[3]-q[1]
            valid=(2<=w<=12 and 2<=h<=11 and .4<w/h<2) if name=='Tato' else(4<=w<=31 and 7<=h<=36)
            if valid:cs.append(c)
        cs=sorted(cs,key=lambda c:centre(c)[1]);assert len(cs)>=2,(name,'eye glyphs not found')
        if name=='Melody':
            pairs=[(a,b) for j,a in enumerate(cs) for b in cs[j+1:] if 18<abs(centre(a)[0]-centre(b)[0])<65 and abs(centre(a)[1]-centre(b)[1])<25]
            assert pairs,(name,'separated eye pair missing')
            chosen=min(pairs,key=lambda p:sum(centre(c)[1] for c in p)/2)
        else:chosen=cs[:2]
        eyes=[centre(c) for c in chosen];cx=float(np.mean([p[0] for p in eyes]));cy=float(np.mean([p[1] for p in eyes]))
        if name=='Tato':
            face=(alpha>180)&(abs(r-g)<18)&(abs(g-b)<18)&(abs(yy-cy)<3)&(abs(xx-cx)<72)
        else:
            face=(alpha>180)&(r>170)&(g>100)&(r-g>25)&(abs(g-b)<18)&(abs(yy-cy)<3)&(abs(xx-cx)<72)
        ys,xs=np.nonzero(face);assert len(xs)>10,(name,'head cross section missing')
        left,right=int(xs.min()),int(xs.max())
        row=alpha[round(cy)]>180;x=round(cx);left=right=x
        while left>0 and row[left-1]:left-=1
        while right<543 and row[right+1]:right+=1
        if right-left>115:
                row=(alpha[round(cy)]>180)&((abs(r[round(cy)]-g[round(cy)])<32)&(abs(g[round(cy)]-b[round(cy)])<22) if name=='Tato' else (r[round(cy)]-g[round(cy)]>25)&(abs(g[round(cy)]-b[round(cy)])<12))
                for start in range(1,535):
                    if row[start-1] and not row[start]:
                        end=start
                        while end<544 and not row[end]:end+=1
                        if end-start<=(8 if name=='Tato' else 25) and end<544:row[start:end]=True
                left=right=x
                while left>0 and row[left-1]:left-=1
                while right<543 and row[right+1]:right+=1
        result[name]={'face_cross_section_width':right-left+1,'eye_centres':eyes,'cross_section_y':round(cy,2),'cross_section_x':[left,right]}
    return result
