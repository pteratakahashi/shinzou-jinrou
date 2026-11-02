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

-- レート計算（イロレーティング、K=32）。試合を確定させる。
create or replace function public._decide(m public.matches, w uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  l uuid := case when w = m.p1 then m.p2 else m.p1 end;
  rw integer; rl integer; d integer; gw integer; gl integer;
begin
  select rating into rw from players where id = w for update;
  select rating into rl from players where id = l for update;
  d := greatest(1, round(32 * (1 - 1 / (1 + power(10, (rl - rw) / 400.0))))::integer);
  gw := d + 8;                      -- 勝ち：格上に勝つほど多い（約12〜40）
  gl := greatest(4, d - 6);         -- 負け：格下に負けるほど多い（4〜26）
  update players set rating = rating + d, rp = rp + gw, wins = wins + 1, updated_at = now() where id = w;
  update players set rating = greatest(0, rating - d), rp = greatest(0, rp - gl), losses = losses + 1, updated_at = now() where id = l;
  update matches set winner = w, status = 'done', delta = d, rp_win = gw, rp_loss = gl, decided_at = now() where id = m.id;
end $$;

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

-- ログイン直後に呼ぶ。自分の行がなければ作り、名前を合わせて、自分の成績を返す。
create or replace function public.my_profile(p_name text default null)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r json;
begin
  if me is null then raise exception 'not signed in'; end if;
  perform _settle_stale();
  insert into players(id, name) values (me, coalesce(nullif(left(trim(p_name), 10), ''), 'プレイヤー'))
    on conflict (id) do nothing;
  if p_name is not null and length(trim(p_name)) > 0 then
    update players set name = left(regexp_replace(trim(p_name), '[<>&"]', '', 'g'), 10), updated_at = now()
      where id = me and name is distinct from left(regexp_replace(trim(p_name), '[<>&"]', '', 'g'), 10);
  end if;
  select json_build_object(
    'id', p.id, 'name', p.name, 'rating', p.rating, 'rp', p.rp, 'wins', p.wins, 'losses', p.losses,
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

-- 対戦が始まったら両方のブラウザが呼ぶ。両方そろった試合だけが結果を報告できる。
create or replace function public.start_match(p_match text, p_opp uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); a uuid; b uuid; m public.matches;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_opp is null or p_opp = me then raise exception 'bad opponent'; end if;
  if length(p_match) < 8 or length(p_match) > 64 then raise exception 'bad match id'; end if;
  insert into players(id) values (me) on conflict (id) do nothing;
  if not exists (select 1 from players where id = p_opp) then raise exception 'opponent not registered'; end if;
  a := least(me, p_opp); b := greatest(me, p_opp);
  insert into matches(id, p1, p2) values (p_match, a, b) on conflict (id) do nothing;
  select * into m from matches where id = p_match for update;
  if m.p1 <> a or m.p2 <> b then raise exception 'match belongs to other players'; end if;
  if me = a then update matches set p1_in = true where id = p_match;
  else update matches set p2_in = true where id = p_match; end if;
end $$;

-- 対戦が終わったら両方のブラウザが呼ぶ。p_winner は自分から見た勝者のID。
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
  if m.status <> 'pending' then return json_build_object('status', m.status, 'delta', case when m.winner = me then m.rp_win else m.rp_loss end, 'won', m.winner = me); end if;
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
  return json_build_object('status', m.status, 'delta', case when m.winner = me then m.rp_win else m.rp_loss end, 'won', m.winner = me);
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

-- ランクマッチ：待機列に入る／待機を続ける。数秒ごとに呼ぶ。
-- 自分より前から待っている人がいれば、その人を確保して部屋コードを返す（後から来た側が先に来た側に入る）
create or replace function public.mm_poll(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); my public.queue; t public.queue; r integer;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_code !~ '^[A-Z0-9]{5}$' then raise exception 'bad code'; end if;
  insert into players(id) values (me) on conflict (id) do nothing;
  select rating into r from players where id = me;
  delete from queue where seen_at < now() - interval '20 seconds';
  insert into queue(uid, code, rating) values (me, p_code, r)
    on conflict (uid) do update set code = excluded.code, rating = excluded.rating, seen_at = now(),
      created_at = case when queue.code = excluded.code then queue.created_at else now() end;
  select * into my from queue where uid = me for update;
  if my.claimed_by is not null then
    if my.claimed_at > now() - interval '25 seconds' then return json_build_object('state', 'claimed'); end if;
    update queue set claimed_by = null, claimed_at = null where uid = me;   -- 相手が来なかった
  end if;
  select * into t from queue
    where uid <> me and claimed_by is null and seen_at > now() - interval '20 seconds'
      and (created_at, uid) < (my.created_at, me)
    order by abs(rating - r), created_at
    limit 1 for update skip locked;
  if found then
    update queue set claimed_by = me, claimed_at = now() where uid = t.uid;
    delete from queue where uid = me;
    return json_build_object('state', 'join', 'code', t.code);
  end if;
  return json_build_object('state', 'wait', 'waiting', (select count(*) from queue where seen_at > now() - interval '20 seconds'));
end $$;

create or replace function public.mm_leave()
returns void language sql security definer set search_path = public as $$
  delete from queue where uid = auth.uid();
$$;

revoke all on function public._decide(public.matches, uuid) from public, anon, authenticated;
revoke all on function public._settle_stale() from public, anon, authenticated;
grant execute on function public.my_profile(text) to authenticated;
grant execute on function public.start_match(text, uuid) to authenticated;
grant execute on function public.report_result(text, uuid, uuid, text) to authenticated;
grant execute on function public.leaderboard(integer) to anon, authenticated;
grant execute on function public.mm_poll(text) to authenticated;
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
