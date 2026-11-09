"""Locate only eye regions in each retained frontal pose for protected eyelid edits."""
import numpy as np

def components(mask,offset):
    h,w=mask.shape;bits=bytearray(mask.tobytes());out=[]
    for start in np.flatnonzero(mask):
        if not bits[start]:continue
        todo=[int(start)];bits[start]=0;pts=[]
        while todo:
            p=todo.pop();pts.append(p);x=p%w;y=p//w
            for dy in (-1,0,1):
                for dx in (-1,0,1):
                    if not (dx or dy):continue
                    xx=x+dx;yy=y+dy
                    if 0<=xx<w and 0<=yy<h:
                        q=yy*w+xx
                        if bits[q]:bits[q]=0;todo.append(q)
        if len(pts)>=5:
            ys=np.asarray(pts)//w;xs=np.asarray(pts)%w
            out.append({'area':len(pts),'box':[int(xs.min())+offset[0],int(ys.min())+offset[1],int(xs.max()+1)+offset[0],int(ys.max()+1)+offset[1]]})
    return out

def locate(im,record):
    a=np.asarray(im.convert('RGBA'));rgb=a[:,:,:3].astype(int);r,g,b=[rgb[:,:,i] for i in range(3)]
    main_y=record['ear_proxy_before_y']+record['whole_character_translation_px'][1]+124
    tato_y=record['attachment_proxies']['tato_foot'][1]-103
    melody_y=record['attachment_proxies']['melody_foot'][1]-106
    result={}
    for actor,y,windows in [('retto',main_y,[(175,255),(270,350)]),('tato',tato_y,[(25,94),(91,155)]),('melody',melody_y,[(385,451),(448,525)])]:
        for side,(x0,x1) in enumerate(windows):
            y0=max(0,int(y)-26);y1=min(544,int(y)+23)
            if actor=='retto':mask=(r<150)&(g<125)&(b<125)&((r+g+b)<330)
            elif actor=='tato':mask=(r<90)&(g<90)&(b<90)
            else:mask=(r>60)&(r<230)&(g<90)&(b<120)&(r>g*1.5)&(r>b*1.3)
            mask=mask&(a[:,:,3]>128)
            found=components(mask[y0:y1,x0:x1],(x0,y0))
            assert found,(record['id'],actor,side,'eye not found')
            if actor=='retto':chosen=max(found,key=lambda v:v['area'])
            else:
                # Eyes occur above the mouth/collar/bow in these frontal faces.
                meaningful=[v for v in found if v['area']>=8] or found
                chosen=min(meaningful,key=lambda v:v['box'][1])
            result[f'{actor}_{side}']=chosen['box']
    return result
