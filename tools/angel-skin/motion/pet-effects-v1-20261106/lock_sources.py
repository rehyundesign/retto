"""Capture PRE-EDIT seven-state sources and attachment/color landmarks."""
from pathlib import Path
from urllib.parse import unquote
import json,re,hashlib
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent
GALLERY=ROOT.parents[1]/'review-gallery-20261105'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n')
def components(m):
    seen=np.zeros(m.shape,bool);out=[]
    for y,x in zip(*np.nonzero(m)):
        if seen[y,x]:continue
        stack=[(y,x)];seen[y,x]=True;pts=[]
        while stack:
            yy,xx=stack.pop();pts.append((yy,xx))
            for dy,dx in [(-1,0),(1,0),(0,-1),(0,1)]:
                ny,nx=yy+dy,xx+dx
                if 0<=ny<m.shape[0] and 0<=nx<m.shape[1] and m[ny,nx] and not seen[ny,nx]:seen[ny,nx]=True;stack.append((ny,nx))
        if len(pts)>=12:out.append(pts)
    return out

def anchor(im,actor):
    a=np.asarray(im).astype(int);r,g,b,alpha=[a[:,:,i] for i in range(4)];yy,xx=np.indices(r.shape)
    if actor=='tato':
        mask=(r>140)&(r>g*1.08)&(g>b*1.5)&(g>80)&(xx<185)&(xx>20)&(yy>270)&(alpha>200)
    else:mask=(r>100)&(r>g*1.8)&(r>b*1.15)&(g<140)&(b<170)&(xx>365)&(yy>300)&(alpha>200)
    cs=components(mask);assert cs,actor
    # Bell/bow are larger than isolated fur flecks/closed eye lines in these neck windows.
    pts=max(cs,key=len);ys,xs=zip(*pts);cx=float(np.mean(xs));cy=float(np.mean(ys))
    if actor=='melody':
        # The high central portion is the bow knot; long streaming tails are secondary.
        top=min(ys);p=[(y,x) for y,x in pts if y<top+(max(ys)-top)*.55]
        if p:cy=float(np.mean([y for y,x in p]));cx=float(np.mean([x for y,x in p]))
    return [round(cx,2),round(cy,2)]

def main():
    assert not (ROOT/'pre-edit-lock.json').exists(),'Never overwrite a pre-edit lock'
    html=(GALLERY/'index.html').read_text();data=json.loads(re.search(r'<script id="media-data" type="application/json">(.*?)</script>',html,re.S).group(1));current=[x for x in data if x['status']!='archive'];assert len(current)==7
    lock={};board=Image.new('RGB',(4*544,7*568),'#10182a');d=ImageDraw.Draw(board)
    for row,item in enumerate(current):
        state=item['state'];out=ROOT/state;out.mkdir(exist_ok=True)
        char=(GALLERY/unquote(item['character']['src'].split('?')[0])).resolve();full=(GALLERY/unquote(item['effect']['src'].split('?')[0])).resolve()
        folder=char.parent if char.parent.name in ['idle','waiting','failed','waving'] else char.parent.parent
        pngs=[folder/'character'/f'{i:02}.png' for i in range(16)];assert all(p.exists() for p in pngs)
        ims=[];times=[];points=[]
        with Image.open(char) as im:
            assert im.n_frames==16
            for i in range(16):
                im.seek(i);im.load();f=im.convert('RGBA');ims.append(f);times.append(im.info['duration'])
                points.append({actor:anchor(f,actor) for actor in ['tato','melody']})
        sources=[{'id':f'{i:02}','path':str(p),'sha256':sha(p)} for i,p in enumerate(pngs)]
        write(out/'character-lock.json',{'source_sha256':{s['id']:s['sha256'] for s in sources}})
        write(out/'retained-map.json',{'sources':sources,'playback_ids':[f'{i:02}' for i in range(16)],'pose_durations_ms':times})
        write(out/'attachments.json',{'method':'gold bell / red bow color-component neck proxies, all16 locations reviewed on marked character boards; no body registration claim','points':points})
        lock[state]={'character':str(char),'character_sha256':sha(char),'effect':str(full),'effect_sha256':sha(full),'sources':sources,'pose_durations_ms':times,'cycle_ms':sum(times),'previous_gallery_item':item}
        for col,i in enumerate([0,4,8,12]):
            tile=Image.new('RGBA',(544,544),'#10182a');tile.alpha_composite(ims[i]);painter=ImageDraw.Draw(tile)
            for actor,color in [('tato','#62cfff'),('melody','#ff5174')]:
                x,y=points[i][actor];painter.ellipse((x-5,y-5,x+5,y+5),outline=color,width=2)
            board.paste(tile.convert('RGB'),(col*544,row*568));d.text((col*544+6,row*568+548),state+' '+str(i),fill='#b9a37f')
    write(ROOT/'pre-edit-lock.json',lock);board.thumbnail((1200,2200));board.save(ROOT/'attachments-review.png');print({s:{'tato_range':[min(p['tato'][1] for p in json.loads((ROOT/s/'attachments.json').read_text())['points']),max(p['tato'][1] for p in json.loads((ROOT/s/'attachments.json').read_text())['points'])]} for s in lock})
if __name__=='__main__':main()
