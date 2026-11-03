from pathlib import Path
import json
root=Path(__file__).resolve().parent
# Top-left positions in the real448x640 character cell; fairy cell is90x90.
plans={
'idle':(0,3.2,'right','tie adjustment → Ran leans in → shared glance and cheer',[(0,328,361,0),(2,322,380,1),(4,300,425,2),(6,278,446,3),(8,292,412,4),(10,305,360,5),(12,321,355,6),(14,328,361,7),(16,328,361,0)]),
'drag-right':(1,1.6,'right','Ran leads near the muzzle and looks back toward Retto',[(0,335,366,0),(2,332,361,1),(4,334,366,2),(6,335,371,3),(8,335,366,4),(10,332,361,5),(12,334,366,6),(14,335,371,7),(16,335,366,0)]),
'drag-left':(2,1.6,'left','Ran leads near the muzzle and looks back toward Retto',[(0,22,366,0),(2,25,361,1),(4,23,366,2),(6,22,371,3),(8,22,366,4),(10,25,361,5),(12,23,366,6),(14,22,371,7),(16,22,366,0)]),
'waving':(3,2.4,'left','approach raised paw → pompom high-five → cheer with wink → settle',[(0,14,470,0),(2,14,450,1),(4,12,415,2),(6,12,376,2),(7,12,365,3),(8,12,368,4),(9,14,382,5),(10,15,393,5),(12,15,427,6),(14,14,462,7),(16,14,470,0)]),
'jumping':(4,2.4,'left','Ran anticipates with Retto, rises with takeoff and celebrates landing',[(0,15,470,0),(2,15,480,1),(4,14,435,2),(6,14,382,5),(8,16,368,5),(10,16,404,4),(12,15,461,6),(14,15,470,7),(16,15,470,0)]),
'failed':(5,3.2,'left','Ran meets the offered forepaw, reassures and cheers',[(0,16,450,0),(2,14,460,1),(4,12,468,2),(6,12,463,3),(8,12,451,4),(10,14,430,5),(12,16,438,6),(14,16,450,7),(16,16,450,0)]),
'waiting':(6,3.2,'right','inspect armband tap → rise into Retto glance → acknowledge together',[(0,324,365,0),(2,310,401,1),(4,276,438,2),(6,254,444,3),(8,270,421,4),(10,295,363,5),(12,310,358,6),(14,324,365,7),(16,324,365,0)]),
'running':(7,2.4,'left','Ran meets the raised forepaw and cheers the heart-unlock preparation',[(0,14,505,0),(2,22,495,1),(4,38,480,2),(6,48,460,3),(8,43,445,3),(10,12,445,5),(12,12,459,6),(14,14,505,7),(16,14,505,0)]),
'review':(8,3.2,'left','Ran peers down at the heart held by Retto and gives a small pompom tap',[(0,16,485,0),(2,28,477,1),(4,55,448,2),(6,65,443,3),(8,62,448,3),(10,48,459,4),(12,28,470,5),(14,16,481,7),(16,16,485,0)]),
'sleeping':(11,6.4,'sleep','Ran rests tucked against the curled tail and breathes with Retto',[(0,68,468,0),(2,68,469,1),(4,68,470,2),(6,68,471,3),(8,68,471,4),(10,68,470,5),(12,68,469,6),(14,68,468,7),(16,68,468,0)])}
rows={}
for state,(row,cycle,side,action,keys) in plans.items():
 frames=[]
 for i in range(16):
  a=max(k for k in keys if k[0]<=i);b=min(k for k in keys if k[0]>i);u=(i-a[0])/(b[0]-a[0]);frames.append({'x':a[1]+(b[1]-a[1])*u,'y':a[2]+(b[2]-a[2])*u,'pose':a[3]})
 if state in ['drag-right','drag-left']:
  for frame in frames:frame['y']-=100  # lead above the muzzle, never cover the eyes
 if state=='waving':
  for frame in frames:frame['y']+=24  # pompom meets the paw/cuff edge; fairy face stays below pads
 rows[str(row)]={'id':state,'cycle':cycle,'side':side,'action':action,'frames':frames}
plan={'version':1,'cell':[448,640],'companion_cell':[90,90],'clock':'positions/response follow character pose time; continuous breathing follows independent effect time','rows':rows,'gaze':{'school':{'x':315,'y':350,'side':'right'},'heart':{'x':315,'y':365,'side':'right'}},'sleep_pose_source':'existing8 independent sleepy drawings','source_queue':'motion/queue-ran-interactions-v1.json'}
plan['effects']={'0': {'anchor': [278, 481], 'mode': 'glint', 'peak': 0.38, 'width': 0.22, 'strength': 0.6}, '1': {'anchor': [105, 590], 'mode': 'glint', 'peak': 0.5, 'width': 0.3, 'strength': 0}, '2': {'anchor': [343, 590], 'mode': 'glint', 'peak': 0.5, 'width': 0.3, 'strength': 0}, '3': {'anchor': [89, 425], 'mode': 'heart', 'peak': 0.46, 'width': 0.16, 'strength': 1}, '4': {'anchor': [170, 604], 'mode': 'ring', 'peak': 0.5, 'width': 0.32, 'strength': 1}, '5': {'anchor': [86, 516], 'mode': 'heart', 'peak': 0.56, 'width': 0.22, 'strength': 0.65}, '6': {'anchor': [260, 485], 'mode': 'signal', 'peak': 0.38, 'width': 0.2, 'strength': 0.85}, '7': {'anchor': [126, 498], 'mode': 'heart', 'peak': 0.43, 'width': 0.21, 'strength': 0.8}, '8': {'anchor': [150, 475], 'mode': 'glint', 'peak': 0.43, 'width': 0.2, 'strength': 0.85}, '11': {'anchor': [47, 490], 'mode': 'glint', 'peak': 0.5, 'width': 0.5, 'strength': 0}}
(root/'plan.json').write_text(json.dumps(plan,indent=2)+'\n');print('10 state-specific partner-response tracks')
