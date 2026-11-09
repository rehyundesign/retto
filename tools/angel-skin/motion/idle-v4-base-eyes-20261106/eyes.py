"""Locate neutral/dark blue-grey main irises, never pet eyes or whole head masks."""
import numpy as np

def components(mask):
    seen=np.zeros(mask.shape,bool);h,w=mask.shape;out=[]
    for y,x in zip(*np.nonzero(mask)):
        if seen[y,x]:continue
        seen[y,x]=True;todo=[(y,x)];pts=[]
        while todo:
            yy,xx=todo.pop();pts.append((yy,xx))
            for dy,dx in [(-1,0),(1,0),(0,-1),(0,1)]:
                ny,nx=yy+dy,xx+dx
                if 0<=ny<h and 0<=nx<w and mask[ny,nx] and not seen[ny,nx]:seen[ny,nx]=True;todo.append((ny,nx))
        if len(pts)>=5:out.append(pts)
    return out

def locate(im,roi=(185,150,335,265)):
    a=np.asarray(im).astype(int);r,g,b,alpha=[a[:,:,i] for i in range(4)];yy,xx=np.indices(alpha.shape);x0,y0,x1,y1=roi
    mask=(r<160)&(g<165)&(b<175)&(g>=r*.85)&(b>=r*.85)&(alpha>220)&(xx>=x0)&(xx<x1)&(yy>=y0)&(yy<y1)
    cs=components(mask)
    def center(c):return [float(np.mean([x for y,x in c])),float(np.mean([y for y,x in c]))]
    pairs=[]
    for i,c in enumerate(cs):
        for d in cs[i+1:]:
            ca,cb=center(c),center(d);dx=abs(ca[0]-cb[0]);dy=abs(ca[1]-cb[1])
            if 28<dx<95 and dy<35:pairs.append((len(c)+len(d),c,d))
    assert pairs,'cannot locate two main irises'
    _,c,d=max(pairs,key=lambda p:p[0]);chosen=sorted([c,d],key=lambda c:center(c)[0]);result=[]
    for c in chosen:
        ys,xs=zip(*c);result.append({'bbox':[int(min(xs)),int(min(ys)),int(max(xs)+1),int(max(ys)+1)],'center':center(c),'pixels':len(c)})
    return result
