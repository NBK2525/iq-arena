-- =========================================================
-- IQ ARENA ランキング用の設定
-- Supabase の「SQL Editor」にこのファイルの中身を全部貼り付けて「Run」を押す。
-- 何度実行しても壊れないように書いてある。
-- =========================================================

-- 記録を保存する表
create table if not exists public.iqa_scores (
  id          bigint generated always as identity primary key,
  player_id   uuid        not null,               -- ブラウザごとのランダムなID
  nickname    text        not null,
  difficulty  text        not null check (difficulty in ('easy', 'normal', 'hard')),
  total_ms    integer     not null,               -- 合計タイム（ミリ秒）
  stage_ms    integer[]   not null,               -- ステージ1〜5のタイム（ミリ秒）
  code        text,                               -- 問題コード
  created_at  timestamptz not null default now()
);
create index if not exists iqa_scores_rank_idx   on public.iqa_scores (difficulty, total_ms);
create index if not exists iqa_scores_player_idx on public.iqa_scores (player_id, created_at desc);

-- 表への直接の読み書きは禁止。下の2つの関数だけを入口にする。
alter table public.iqa_scores enable row level security;
revoke all on public.iqa_scores from anon, authenticated;

-- ---------------------------------------------------------
-- 記録を登録する。ありえない記録や連続投稿はここで弾く。
-- 戻り値：{ rank: 自己ベストの順位, players: 参加人数, best_ms: 自己ベスト, total_ms: 今回のタイム }
-- ---------------------------------------------------------
create or replace function public.iqa_submit_score(
  p_player     uuid,
  p_nickname   text,
  p_difficulty text,
  p_stage_ms   integer[],
  p_code       text default null
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nick    text := btrim(coalesce(p_nickname, ''));
  v_total   integer;
  v_last    timestamptz;
  v_best    integer;
  v_rank    integer;
  v_players integer;
  v_s       integer;
begin
  if p_player is null then
    raise exception 'player_required';
  end if;
  if char_length(v_nick) < 1 or char_length(v_nick) > 12 then
    raise exception 'nickname_length';
  end if;
  if p_difficulty not in ('easy', 'normal', 'hard') then
    raise exception 'difficulty_invalid';
  end if;
  if p_stage_ms is null or array_length(p_stage_ms, 1) is distinct from 5 then
    raise exception 'stages_invalid';
  end if;
  -- 1ステージ2秒未満・30分超は受け付けない
  foreach v_s in array p_stage_ms loop
    if v_s is null or v_s < 2000 or v_s > 1800000 then
      raise exception 'stage_time_invalid';
    end if;
  end loop;
  if p_code is not null and char_length(p_code) > 40 then
    raise exception 'code_invalid';
  end if;

  -- 同じプレイヤーは20秒に1回まで
  select max(s.created_at) into v_last from iqa_scores s where s.player_id = p_player;
  if v_last is not null and v_last > now() - interval '20 seconds' then
    raise exception 'too_frequent';
  end if;

  select sum(x) into v_total from unnest(p_stage_ms) as x;

  insert into iqa_scores (player_id, nickname, difficulty, total_ms, stage_ms, code)
  values (p_player, v_nick, p_difficulty, v_total, p_stage_ms, p_code);

  -- 自己ベストでの順位
  with best as (
    select s.player_id, min(s.total_ms) as b
    from iqa_scores s
    where s.difficulty = p_difficulty
    group by s.player_id
  )
  select
    (select b from best where best.player_id = p_player),
    (select count(*) from best)
  into v_best, v_players;

  select count(*) + 1 into v_rank
  from (
    select s.player_id, min(s.total_ms) as b
    from iqa_scores s
    where s.difficulty = p_difficulty
    group by s.player_id
  ) t
  where t.b < v_best;

  return json_build_object('rank', v_rank, 'players', v_players, 'best_ms', v_best, 'total_ms', v_total);
end;
$$;

-- ---------------------------------------------------------
-- ランキングを取得する。1人1行（自己ベスト）。
-- 上位 p_limit 件に加えて、自分が圏外なら自分の行も返す。
-- ---------------------------------------------------------
create or replace function public.iqa_leaderboard(
  p_difficulty text,
  p_player     uuid    default null,
  p_limit      integer default 20
) returns table (
  rank       bigint,
  nickname   text,
  total_ms   integer,
  stage_ms   integer[],
  created_at timestamptz,
  is_me      boolean
)
language sql
security definer
set search_path = public
stable
as $$
  with best as (
    select distinct on (s.player_id)
      s.player_id, s.nickname, s.total_ms, s.stage_ms, s.created_at
    from iqa_scores s
    where s.difficulty = p_difficulty
    order by s.player_id, s.total_ms asc, s.created_at asc
  ),
  ranked as (
    select
      rank()       over (order by b.total_ms asc)                 as rk,
      row_number() over (order by b.total_ms asc, b.created_at asc) as rn,
      b.nickname, b.total_ms, b.stage_ms, b.created_at,
      coalesce(b.player_id = p_player, false)                     as me
    from best b
  )
  select r.rk, r.nickname, r.total_ms, r.stage_ms, r.created_at, r.me
  from ranked r
  where r.rn <= least(greatest(coalesce(p_limit, 20), 1), 100) or r.me
  order by r.rn;
$$;

-- 誰でも（ログインなしで）呼べるのはこの2つの関数だけ
revoke all on function public.iqa_submit_score(uuid, text, text, integer[], text) from public;
revoke all on function public.iqa_leaderboard(text, uuid, integer) from public;
grant execute on function public.iqa_submit_score(uuid, text, text, integer[], text) to anon, authenticated;
grant execute on function public.iqa_leaderboard(text, uuid, integer) to anon, authenticated;
