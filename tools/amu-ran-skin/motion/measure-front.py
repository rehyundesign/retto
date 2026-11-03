from PIL import Image
import numpy as np
import statistics
def components(mask):
    remaining=set(map(tuple,np.argwhere(mask)));found=[]
    while remaining:
        point=remaining.pop();todo=[point];part=[point]
        while todo:
            y,x=todo.pop()
            for p in [(y-1,x),(y+1,x),(y,x-1),(y,x+1)]:
                if p in remaining:remaining.remove(p);todo.append(p);part.append(p)
        if len(part)>12:
            y,x=np.asarray(part).mean(axis=0);found.append((len(part),float(x),float(y)))
    return sorted(found,reverse=True)

def measure(im,name):
    a=np.asarray(im).astype(float);r,g,b,alpha=[a[:,:,i] for i in range(4)]
    blue=(b-r>12)&(g-r>5)&(alpha>128)
    blue[:120]=False;blue[430:]=False
    blobs=components(blue);pairs=[]
    for i,p in enumerate(blobs):
        for q in blobs[i+1:]:
            # A real bow/head tilt can put the two irises on different rows.
            # Keep horizontal separation strict so two fragments of one iris never pair.
            if 40<abs(p[1]-q[1])<130 and abs(p[2]-q[2])<45:
                pairs.append((p[0]+q[0],(p[1]+q[1])/2,(p[2]+q[2])/2))
    if pairs:
        _,cx,eye=max(pairs)
    else:
        # Full blink: nose stays articulated with the actual whole head.
        pink=(r-g>25)&(b-g>-15)&(g>90)&(alpha>128)
        pink[:310]=False;pink[430:]=False;pink[:,:110]=False;pink[:,245:]=False
        blobs=components(pink)
        assert blobs, (name,'no facial landmark detected')
        _,cx,ny=blobs[0];eye=ny-29
    spans=[];centers=[]
    for y in range(round(eye+8),round(eye+23)):
        fur=(g[y]-b[y]>2)&(r[y]-g[y]>-10)&(r[y]-g[y]<75)&(alpha[y]>110)
        xs=np.flatnonzero(fur)
        xs=xs[(xs>cx-160)&(xs<cx+160)]
        if len(xs):spans.append(int(xs[-1]-xs[0]+1));centers.append(float((xs[-1]+xs[0])/2))
    width=statistics.median(spans);center=statistics.median(centers)
    # Grounded foreleg and rear support soles, excluding the tail.
    lo,hi=round(center-width*.36),round(center+width*.36)
    ys,xs=np.nonzero(alpha[round(eye+100):,lo:hi]>96)
    assert len(ys),(name,'no support paw')
    foot=round(eye+100)+int(ys.max())
    # Viewer-right forepaw stays grounded throughout the tie-adjusting sequence.
    lo,hi=max(0,round(center+5)),min(448,round(center+width*.44))
    fy,fx=np.nonzero(alpha[max(0,foot-10):foot+1,lo:hi]>96)
    support=float(np.mean(fx)+lo) if len(fx) else center+40
    return {'eye_center_x':cx,'cheek_width':width,'head_center_x':center,'eye_line':eye,'foot_baseline':foot,'support_toe_x':support}
