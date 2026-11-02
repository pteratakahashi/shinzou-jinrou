from PIL import Image
from collections import deque
import sys,math
# 顔の左右端・目の高さ・あごの高さ（元画像126px座標）。aは動物
F=dict(alchemist=(45,73,45,73),apprentice=(52,90,66,86),assassin=(44,84,58,None),astrologer=(46,80,52,76),baker=(49,86,52,72),bard=(47,89,54,80),
bastion=(53,74,52,70),bodyguard=(52,80,52,77),chief=(43,88,43,76),cryboy=(52,80,52,76),curser=(50,82,48,75),
decoy=(47,77,39,66),detective=(48,82,58,82),elder=(50,80,42,72),executioner=(52,94,47,None),fox=(48,84,58,84),gatekeeper=(55,90,45,75),
greatdet=(45,76,45,72),hunter=(46,88,52,82),inquisitor=(44,86,55,81),madman=(46,84,47,80),medium=(46,78,46,78),
mirror=(46,76,42,70),necro=(45,84,54,83),oracle=(47,80,50,80),peddler=(43,90,55,87),
phantom=(44,90,52,87),poisoner=(48,80,47,77),priest=(50,80,39,63),prophet=(53,88,39,70),reflect=(46,80,48,80),sage=(46,82,48,77),
saint=(47,80,44,74),seer=(46,84,52,79),sentinel=(46,86,58,87),silencer=(48,80,45,73),spy=(46,80,57,85),teller=(46,86,50,76),
timewitch=(48,82,50,76),trapper=(46,84,46,76),vampire=(48,82,46,84),villager=(39,92,59,88),warder=(46,82,47,78))
A=dict(cursewolf=(50,86,47,80),greatwolf=(42,86,47,73),nekomata=(36,98,61,80),pack=(46,90,52,82),watchdog=(42,92,52,81),whitewolf=(38,89,47,72),wolf=(45,88,47,77))
FACE2=dict(twins=(63,52,30),mason=(67,45,47))
TW,TH,AW,AH=34,28,40,28
TCX,TMID=63,60
BG=(169,155,118);OUT=252;src=sys.argv[1]
def load(k):
  im=Image.open(f'{src}/{k}.png').convert('RGBA');w,h=im.size;px=im.load()
  seen=set();q=deque([(x,y) for x in range(w) for y in (0,h-1)]+[(x,y) for y in range(h) for x in (0,w-1)])
  while q:
    x,y=q.popleft()
    if (x,y) in seen or not(0<=x<w and 0<=y<h):continue
    seen.add((x,y));r,g,b,a=px[x,y]
    if abs(r-BG[0])+abs(g-BG[1])+abs(b-BG[2])>6:continue
    px[x,y]=(0,0,0,0);q.extend([(x+1,y),(x-1,y),(x,y+1),(x,y-1)])
  return im
def place(k,cx,mid,s):
  im=load(k);w,h=im.size
  ext=Image.new('RGBA',(w*3,h*3),(0,0,0,0));ext.paste(im,(w,h))
  row=im.crop((0,h-1,w,h))
  for i,yy in enumerate(range(2*h,2*h+18)):
    r2=row.copy();al=r2.getchannel('A').point(lambda v,f=1-(i+1)/18:int(v*f));r2.putalpha(al);ext.paste(r2,(w,yy))
  Fz=8;big=ext.resize((w*3*Fz,h*3*Fz),Image.NEAREST)
  sw=126/s;x0=cx-TCX/s+w;y0=mid-TMID/s+h
  box=tuple(int(round(v*Fz)) for v in (x0,y0,x0+sw,y0+sw))
  big.crop(box).resize((OUT,OUT),Image.BOX).save(f'art/{k}.png',optimize=True)
# 名探偵を基準に、1枚ずつ見比べた補正（倍率, 上下ずれpx, 左右ずれpx：出力252px基準）
ADJ=dict(alchemist=(1,-4,0),apprentice=(.92,-36,0),assassin=(.95,0,0),astrologer=(.95,0,0),baker=(.85,5,0),bard=(.95,0,0),
chief=(.8,-5,0),cryboy=(1,-17,0),curser=(.9,-9,0),decoy=(.92,0,0),detective=(.94,-15,0),elder=(.9,7,0),executioner=(.9,0,0),
fox=(.85,0,15),gatekeeper=(.92,-9,0),greatwolf=(.9,0,0),hunter=(.94,-9,0),inquisitor=(.88,-14,0),madman=(.94,0,0),
medium=(.88,0,0),mirror=(.96,0,0),necro=(.92,0,0),nekomata=(.7,0,0),oracle=(.94,-14,0),pack=(.87,0,0),peddler=(1,-20,0),
phantom=(.85,-20,0),poisoner=(.9,0,0),priest=(.94,-6,0),prophet=(.9,3,0),reflect=(.94,0,0),sage=(.88,0,0),saint=(1,7,0),
seer=(.85,0,0),sentinel=(.94,-8,0),silencer=(.94,0,0),spy=(1,-9,0),teller=(.88,0,0),timewitch=(.86,0,0),trapper=(.94,0,0),
twins=(.62,0,0),villager=(.94,-10,0),watchdog=(.9,-8,0),whitewolf=(1.05,-6,0))
def adj(k,cx,mid,s):
  a=ADJ.get(k,(1,0,0));s2=s*a[0]
  return cx-a[2]/(2*s2),mid-a[1]/(2*s2),s2
out=[]
for k,(l,r,e,c) in {**F,**A}.items():
  tw,th=(AW,AH) if k in A else (TW,TH)
  wd=r-l;cx=(l+r)/2
  if c is None: s=tw/wd;mid=e+th/2/s*s/ (tw/wd) if False else e+14
  else: s=math.sqrt((tw/wd)*(th/(c-e)));mid=(e+c)/2
  s=max(.75,min(1.4,s))
  cx,mid,s=adj(k,cx,mid,s);place(k,cx,mid,s);out.append((k,round(s,2)))
for k,(cx,ey,fw) in FACE2.items():
  s=max(.78,min(1.45,44/fw));cx,mid,s=adj(k,cx,ey+14,s);place(k,cx,mid,s);out.append((k,round(s,2)))
print(out)
