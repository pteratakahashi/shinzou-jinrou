#!/usr/bin/env python3
"""index.html のカード一覧から、setup.sql のカード表（cards の一覧・レアリティ tier・スタンダード starter）を作り直す。
カードを足したり、RANK・LEGEND_N を変えたりしたら実行してから、Supabase で setup.sql を流し直す。
    python3 supabase/gen_cards_sql.py
"""
import os,re
D=os.path.dirname(os.path.abspath(__file__))
s=open(os.path.join(D,'..','index.html'),encoding='utf-8').read()
i=s.index('const RAW');j=s.index('\n];',i)
rows=re.findall(r"^\s*\['([^']+)','[^']+','[^']*','([^']+)','([^']+)'",s[i:j],re.M)
R=eval(re.search(r"const RANK=(\[.*?\]);",s).group(1))
L=eval(re.search(r"const LEGEND_N=(\[.*?\]);",s).group(1))
std=re.search(r"STD_SINGLE='([^']+)'",s).group(1)
def tier(k,cat):
    if cat=='one' or k in L:return 'L'
    if k not in R:return 'B'
    x=R.index(k);return 'G' if x<25 else 'S' if x<48 else 'B'
q=open(os.path.join(D,'setup.sql'),encoding='utf-8').read()
ins=',\n'.join(f"  ('{k}', {'true' if c=='one' else 'false'})" for k,c,r in rows)
q=re.sub(r"(insert into public\.cards\(k, single\) values\n).*?(\non conflict \(k\) do update set single = excluded\.single;)",lambda m:m.group(1)+ins+m.group(2),q,count=1,flags=re.S)
tv=',\n  '.join(f"('{k}','{tier(k,c)}')" for k,c,r in rows)
q=re.sub(r"(update public\.cards c set tier = v\.t from \(values\n  ).*?(\n\) as v\(k, t\) where c\.k = v\.k;)",lambda m:m.group(1)+tv+m.group(2),q,count=1,flags=re.S)
st=[k for k,c,r in rows if r=='S']+[std]+['trapper','baker']  # 罠師は前のスタンダード。全員が持っている扱いのまま（index.html の FREE_OWN）
q=re.sub(r"update public\.cards set starter = \(k in \([^)]*\)\);","update public.cards set starter = (k in ("+','.join(f"'{k}'" for k in st)+"));",q,count=1)
open(os.path.join(D,'setup.sql'),'w',encoding='utf-8').write(q)
from collections import Counter
print(len(rows),'種',Counter(tier(k,c) for k,c,r in rows))
