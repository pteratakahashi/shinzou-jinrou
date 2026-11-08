-- 心臓人狼 対人レート用のデータベース設定
-- Supabase の「SQL Editor」にこのファイルの中身を全部貼り付けて「Run」を押してください。
-- 何度実行しても壊れないように書いてあります。

-- プレイヤーごとのレートと戦績
create table if not exists public.players (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default 'プレイヤー',
  rating integer not null default 1500,
  wins integer not null default 0,
  losses integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 1試合ごとの記録。両方のプレイヤーが結果を送り、内容が一致したらレートに反映する。
create table if not exists public.matches (
  id text primary key,
  p1 uuid not null references public.players(id) on delete cascade,
  p2 uuid not null references public.players(id) on delete cascade,
  p1_in boolean not null default false,   -- p1 が対戦開始を登録した
  p2_in boolean not null default false,
  p1_says uuid,            -- p1 が報告した勝者
  p2_says uuid,            -- p2 が報告した勝者
  p1_reason text,
  p2_reason text,
  winner uuid,
  status text not null default 'pending',   -- pending / done / disputed
  delta integer,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
-- ランクポイント（ブロンズ→マスター）。内部レート(rating)とは別に、勝つと多めに増え、負けると少なめに減る
alter table public.players add column if not exists rp integer not null default 0;
alter table public.matches add column if not exists rp_win integer;
alter table public.matches add column if not exists rp_loss integer;

-- ランクマッチの待機列
create table if not exists public.queue (
  uid uuid primary key references public.players(id) on delete cascade,
  code text not null,
  rating integer not null,
  created_at timestamptz not null default now(),
  seen_at timestamptz not null default now(),
  claimed_by uuid,
  claimed_at timestamptz
);
alter table public.queue enable row level security;
revoke all on public.queue from anon, authenticated;

alter table public.players add column if not exists name_at timestamptz;  -- 最後に名前を変えた時刻

create index if not exists matches_p1 on public.matches(p1, created_at desc);
create index if not exists matches_p2 on public.matches(p2, created_at desc);
create index if not exists players_rating on public.players(rating desc);

alter table public.players enable row level security;
alter table public.matches enable row level security;

-- 誰でもランキング（名前・レート・戦績）は見られる。書き込みは下の関数からだけ。
drop policy if exists players_read on public.players;
create policy players_read on public.players for select using (true);
-- 試合記録は自分が出た試合だけ見られる
drop policy if exists matches_read on public.matches;
create policy matches_read on public.matches for select using (auth.uid() in (p1, p2));

revoke insert, update, delete on public.players from anon, authenticated;
revoke insert, update, delete on public.matches from anon, authenticated;

-- 片方しか報告しないまま10分たった試合は、報告どおりに確定させる（負けた側がページを閉じた場合など）
create or replace function public._settle_stale()
returns void language plpgsql security definer set search_path = public as $$
declare m public.matches;
begin
  for m in select * from matches
           where status = 'pending' and created_at < now() - interval '10 minutes'
             and p1_in and p2_in
             and ((p1_says is null) <> (p2_says is null))
           for update skip locked loop
    perform _decide(m, coalesce(m.p1_says, m.p2_says));
  end loop;
end $$;

-- ログイン直後に呼ぶ。自分の行がなければ作り（名前は p_name）、自分の成績を返す。名前の変更は set_name で。
create or replace function public.my_profile(p_name text default null)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r json;
begin
  if me is null then raise exception 'not signed in'; end if;
  perform _settle_stale();
  insert into players(id, name) values (me, coalesce(nullif(left(trim(p_name), 10), ''), 'プレイヤー'))
    on conflict (id) do nothing;
  select json_build_object(
    'id', p.id, 'name', p.name, 'name_at', p.name_at, 'rating', p.rating, 'rp', p.rp, 'wins', p.wins, 'losses', p.losses,
    'pos', (select count(*) + 1 from players q where q.wins + q.losses > 0
             and (q.rp >= 500, case when q.rp >= 500 then q.rating else q.rp end) > (p.rp >= 500, case when p.rp >= 500 then p.rating else p.rp end)),
    'total', (select count(*) from players q where q.wins + q.losses > 0),
    'recent', coalesce((
      select json_agg(x order by x.at desc) from (
        select coalesce(m.decided_at, m.created_at) as at, m.status,
               case when m.winner = me then m.rp_win else m.rp_loss end as delta,
               (m.winner = me) as won,
               (select name from players o where o.id = case when m.p1 = me then m.p2 else m.p1 end) as opp
        from matches m where me in (m.p1, m.p2) and m.p1_in and m.p2_in order by m.created_at desc limit 10
      ) x), '[]'::json)
  ) into r from players p where p.id = me;
  return r;
end $$;

-- ランキング上位
drop function if exists public.leaderboard(integer);
create or replace function public.leaderboard(p_limit integer default 50)
returns table(pos bigint, name text, rating integer, rp integer, wins integer, losses integer)
language sql security definer set search_path = public stable as $$
  select rank() over (order by rp >= 500 desc, case when rp >= 500 then rating else rp end desc),
         name, case when rp >= 500 then rating end, rp, wins, losses
  from players where wins + losses > 0
  order by rp >= 500 desc, case when rp >= 500 then rating else rp end desc
  limit least(greatest(p_limit, 1), 100);
$$;

create or replace function public.mm_leave()
returns void language sql security definer set search_path = public as $$
  delete from queue where uid = auth.uid();
$$;

revoke all on function public._settle_stale() from public, anon, authenticated;
grant execute on function public.my_profile(text) to authenticated;
grant execute on function public.leaderboard(integer) to anon, authenticated;
grant execute on function public.mm_leave() to authenticated;

-- 観戦：いま対戦中の部屋の一覧。部屋を作った人のブラウザが対戦中に20秒ごとに live_beat を呼ぶ。
-- tok は部屋を作った人だけが知っている合言葉で、他人が一覧を書き換えたり消したりできないようにする。
create table if not exists public.live (
  code text primary key,
  names text not null default '',
  tok text not null,
  started_at timestamptz not null default now(),
  seen_at timestamptz not null default now()
);
alter table public.live enable row level security;
revoke all on public.live from anon, authenticated;

create or replace function public.live_beat(p_code text, p_names text, p_tok text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_code !~ '^[A-Z0-9]{5}$' or length(coalesce(p_tok, '')) not between 16 and 64 then raise exception 'bad args'; end if;
  delete from live where seen_at < now() - interval '60 seconds';
  if not exists (select 1 from live where code = p_code) and (select count(*) from live) >= 500 then return; end if;
  insert into live(code, names, tok) values (p_code, left(coalesce(p_names, ''), 40), p_tok)
    on conflict (code) do update set names = excluded.names, seen_at = now()
    where live.tok = excluded.tok;
end $$;

create or replace function public.live_end(p_code text, p_tok text)
returns void language sql security definer set search_path = public as $$
  delete from live where code = p_code and tok = p_tok;
$$;

-- 観戦する試合をランダムに1つ選ぶ。p_not（さっき見ていた試合）はほかに試合がないときだけ選ぶ
create or replace function public.live_pick(p_not text default '')
returns text language sql security definer set search_path = public as $$
  select code from live where seen_at > now() - interval '45 seconds'
  order by (code = coalesce(p_not, '')), random() limit 1;
$$;

grant execute on function public.live_beat(text, text, text) to anon, authenticated;
grant execute on function public.live_end(text, text) to anon, authenticated;
grant execute on function public.live_pick(text) to anon, authenticated;

-- 名前の変更。1日（24時間）に1回まで。
create or replace function public.set_name(p_name text)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n text; t timestamptz;
begin
  if me is null then raise exception 'not signed in'; end if;
  n := left(trim(regexp_replace(coalesce(p_name, ''), '[<>&"]', '', 'g')), 10);
  if n = '' then raise exception 'empty name'; end if;
  insert into players(id, name) values (me, n) on conflict (id) do nothing;
  select name_at into t from players where id = me for update;
  if t is not null and t > now() - interval '1 day' then
    return json_build_object('ok', false, 'next', t + interval '1 day');
  end if;
  update players set name = n, name_at = now(), updated_at = now() where id = me;
  return json_build_object('ok', true, 'name', n, 'at', now());
end $$;
grant execute on function public.set_name(text) to authenticated;


-- ================= カードの所持（ランクマッチの報酬） =================
-- スタンダードデッキの14種（S のカード13種＋名探偵）は全員が最初から持っている扱いで、ここには入れない。
-- ランクマッチ（待機列でつながった試合）が確定すると、勝った人に2種、負けた人に1種、全カードからランダムに配る（かぶることもある）。
-- 合言葉の部屋（友達対戦）は報酬なし。

-- 配る対象のカード。ゲームにカードを足したら、ここにも足してから SQL をもう一度実行する。
create table if not exists public.cards (
  k text primary key,
  single boolean not null default false
);
alter table public.cards enable row level security;
revoke all on public.cards from anon, authenticated;
insert into public.cards(k, single) values
  ('villager', false),
  ('chief', false),
  ('seer', false),
  ('medium', false),
  ('hunter', false),
  ('wolf', false),
  ('fox', false),
  ('mason', false),
  ('baker', false),
  ('detective', false),
  ('elder', false),
  ('trapper', false),
  ('executioner', false),
  ('madman', false),
  ('watchdog', false),
  ('vampire', false),
  ('priest', false),
  ('phantom', false),
  ('alchemist', false),
  ('twins', false),
  ('sage', false),
  ('bard', false),
  ('nekomata', false),
  ('bodyguard', false),
  ('decoy', false),
  ('inquisitor', false),
  ('cursewolf', false),
  ('cryboy', false),
  ('silencer', false),
  ('reflect', false),
  ('prophet', false),
  ('spy', false),
  ('pack', false),
  ('poisoner', false),
  ('bastion', false),
  ('sentinel', false),
  ('peddler', false),
  ('apprentice', false),
  ('gatekeeper', false),
  ('warder', false),
  ('astrologer', false),
  ('necro', false),
  ('assassin', false),
  ('greatdet', true),
  ('curser', true),
  ('saint', true),
  ('oracle', true),
  ('greatwolf', true),
  ('whitewolf', true),
  ('teller', true),
  ('timewitch', true),
  ('mirror', true),
  ('fortune', false),
  ('listener', false),
  ('diviner', false),
  ('tracker', false),
  ('confessor', false),
  ('stargazer', false),
  ('clairvoy', false),
  ('berserker', false),
  ('ghoul', false),
  ('kidnapper', false),
  ('howler', false),
  ('nightmare', false),
  ('wererat', false),
  ('witch', false),
  ('alpha', false),
  ('knight', false),
  ('nun', false),
  ('watchman', false),
  ('shieldbearer', false),
  ('lookout', false),
  ('cleric', false),
  ('exorcist', false),
  ('banker', false),
  ('gravedigger', false),
  ('messenger', false),
  ('tactician', false),
  ('innkeeper', false),
  ('drummer', false),
  ('gambler', false),
  ('moonqueen', true)
on conflict (k) do update set single = excluded.single;

-- 持っているカード。n は手に入れた回数（2以上はかぶり）。
create table if not exists public.collection (
  uid uuid not null references public.players(id) on delete cascade,
  k text not null references public.cards(k) on delete cascade,
  n integer not null default 1,
  got_at timestamptz not null default now(),
  primary key (uid, k)
);
alter table public.collection enable row level security;
revoke all on public.collection from anon, authenticated;

-- ランクマッチでつながった2人の記録。試合がランクマッチかどうかの判定に使う。
create table if not exists public.mm_pairs (
  a uuid not null,
  b uuid not null,
  at timestamptz not null default now()
);
alter table public.mm_pairs enable row level security;
revoke all on public.mm_pairs from anon, authenticated;
create index if not exists mm_pairs_ab on public.mm_pairs(a, b, at desc);

alter table public.matches add column if not exists ranked boolean not null default false;
alter table public.matches add column if not exists rewards json;   -- {"w":[…], "l":[…]}

-- n 種ランダムに配って、配ったカードの配列を返す
create or replace function public._grant(p_uid uuid, p_n integer)
returns json language plpgsql security definer set search_path = public as $$
declare got text[] := '{}'; ck text; i integer;
begin
  for i in 1..p_n loop
    select c.k into ck from cards c order by random() limit 1;
    if ck is null then exit; end if;
    insert into collection as co (uid, k) values (p_uid, ck)
      on conflict on constraint collection_pkey do update set n = co.n + 1, got_at = now();
    got := got || ck;
  end loop;
  return to_json(got);
end $$;

-- レート計算＋ランクマッチなら報酬（_decide を置きかえる）
create or replace function public._decide(m public.matches, w uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  l uuid := case when w = m.p1 then m.p2 else m.p1 end;
  rw integer; rl integer; d integer; gw integer; gl integer; rew json;
begin
  select rating into rw from players where id = w for update;
  select rating into rl from players where id = l for update;
  d := greatest(1, round(32 * (1 - 1 / (1 + power(10, (rl - rw) / 400.0))))::integer);
  gw := d + 8;
  gl := greatest(4, d - 6);
  update players set rating = rating + d, rp = rp + gw, wins = wins + 1, updated_at = now() where id = w;
  update players set rating = greatest(0, rating - d), rp = greatest(0, rp - gl), losses = losses + 1, updated_at = now() where id = l;
  if m.ranked then
    rew := json_build_object('w', _grant(w, 2), 'l', _grant(l, 1));
  end if;
  update matches set winner = w, status = 'done', delta = d, rp_win = gw, rp_loss = gl, rewards = rew, decided_at = now() where id = m.id;
end $$;

-- ランクマッチの待機列（mm_poll を置きかえる）：つながった2人を mm_pairs に記録する
create or replace function public.mm_poll(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); my public.queue; t public.queue; r integer;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_code !~ '^[A-Z0-9]{5}$' then raise exception 'bad code'; end if;
  insert into players(id) values (me) on conflict (id) do nothing;
  select rating into r from players where id = me;
  delete from queue where seen_at < now() - interval '20 seconds';
  delete from mm_pairs where at < now() - interval '1 hour';
  insert into queue(uid, code, rating) values (me, p_code, r)
    on conflict (uid) do update set code = excluded.code, rating = excluded.rating, seen_at = now(),
      created_at = case when queue.code = excluded.code then queue.created_at else now() end;
  select * into my from queue where uid = me for update;
  if my.claimed_by is not null then
    if my.claimed_at > now() - interval '25 seconds' then return json_build_object('state', 'claimed'); end if;
    update queue set claimed_by = null, claimed_at = null where uid = me;
  end if;
  select * into t from queue
    where uid <> me and claimed_by is null and seen_at > now() - interval '20 seconds'
      and (created_at, uid) < (my.created_at, me)
    order by abs(rating - r), created_at
    limit 1 for update skip locked;
  if found then
    update queue set claimed_by = me, claimed_at = now() where uid = t.uid;
    delete from queue where uid = me;
    insert into mm_pairs(a, b) values (least(me, t.uid), greatest(me, t.uid));
    return json_build_object('state', 'join', 'code', t.code);
  end if;
  return json_build_object('state', 'wait', 'waiting', (select count(*) from queue where seen_at > now() - interval '20 seconds'));
end $$;

-- 対戦開始（start_match を置きかえる）：ランクマッチでつながった2人の試合なら ranked にする
create or replace function public.start_match(p_match text, p_opp uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); va uuid; vb uuid; m public.matches; pt tid;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_opp is null or p_opp = me then raise exception 'bad opponent'; end if;
  if length(p_match) < 8 or length(p_match) > 64 then raise exception 'bad match id'; end if;
  insert into players(id) values (me) on conflict (id) do nothing;
  if not exists (select 1 from players where id = p_opp) then raise exception 'opponent not registered'; end if;
  va := least(me, p_opp); vb := greatest(me, p_opp);
  if not exists (select 1 from matches where id = p_match) then
    select x.ctid into pt from mm_pairs x where x.a = va and x.b = vb and x.at > now() - interval '10 minutes' order by x.at desc limit 1;
    insert into matches(id, p1, p2, ranked) values (p_match, va, vb, pt is not null) on conflict (id) do nothing;
    if pt is not null then delete from mm_pairs where ctid = pt; end if;
  end if;
  select * into m from matches where id = p_match for update;
  if m.p1 <> va or m.p2 <> vb then raise exception 'match belongs to other players'; end if;
  if me = va then update matches set p1_in = true where id = p_match;
  else update matches set p2_in = true where id = p_match; end if;
end $$;

-- 結果報告（report_result を置きかえる）：返り値に ranked と、自分がもらったカード got を足す
create or replace function public.report_result(p_match text, p_opp uuid, p_winner uuid, p_reason text default 'ko')
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m public.matches; a uuid; b uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_opp is null or p_opp = me then raise exception 'bad opponent'; end if;
  if p_winner not in (me, p_opp) then raise exception 'bad winner'; end if;
  a := least(me, p_opp); b := greatest(me, p_opp);
  select * into m from matches where id = p_match for update;
  if not found or m.p1 <> a or m.p2 <> b then raise exception 'unknown match'; end if;
  if not (m.p1_in and m.p2_in) then raise exception 'match was not started by both players'; end if;
  if m.status = 'pending' then
    if me = m.p1 and m.p1_says is null then
      update matches set p1_says = p_winner, p1_reason = left(p_reason, 16) where id = p_match;
    elsif me = m.p2 and m.p2_says is null then
      update matches set p2_says = p_winner, p2_reason = left(p_reason, 16) where id = p_match;
    end if;
    select * into m from matches where id = p_match;
    if m.p1_says is not null and m.p2_says is not null then
      if m.p1_says = m.p2_says then
        perform _decide(m, m.p1_says);
      else
        update matches set status = 'disputed', decided_at = now() where id = p_match;
      end if;
      select * into m from matches where id = p_match;
    end if;
  end if;
  return json_build_object('status', m.status, 'delta', case when m.winner = me then m.rp_win else m.rp_loss end, 'won', m.winner = me,
    'ranked', m.ranked, 'got', case when m.rewards is null then null when m.winner = me then m.rewards->'w' else m.rewards->'l' end);
end $$;

-- 自分の持っているカード {"カードのキー": 手に入れた回数, …}
create or replace function public.my_collection()
returns json language sql security definer set search_path = public stable as $$
  select coalesce(json_object_agg(k, n), '{}'::json) from collection where uid = auth.uid();
$$;

revoke all on function public._grant(uuid, integer) from public, anon, authenticated;
revoke all on function public._decide(public.matches, uuid) from public, anon, authenticated;
grant execute on function public.my_collection() to authenticated;
grant execute on function public.mm_poll(text) to authenticated;
grant execute on function public.start_match(text, uuid) to authenticated;
grant execute on function public.report_result(text, uuid, uuid, text) to authenticated;
