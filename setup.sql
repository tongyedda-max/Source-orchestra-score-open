-- =====================================================
-- ORCHESTRA STAND — FULL DATABASE SETUP (idempotent)
-- Safe to re-run. Never destroys existing data.
-- =====================================================

-- 0) Shared passwords (single row)
create table if not exists public.app_passwords(
  id int primary key default 1 check (id=1),
  gate_password  text not null default 'gate-1234',
  edit_password  text not null default 'edit-1234',
  admin_password text not null default 'admin-1234'
);
insert into public.app_passwords(id) values (1) on conflict do nothing;
alter table public.app_passwords enable row level security;

-- 1) Folders & scores
create table if not exists public.folders(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  parent_id uuid references public.folders(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.scores(
  id uuid primary key default gen_random_uuid(),
  title text not null,
  file_path text not null,
  file_size bigint,
  page_count int,
  folder_id uuid references public.folders(id) on delete set null,
  created_at timestamptz not null default now()
);

-- 2) Annotations
create table if not exists public.strokes(
  id uuid primary key default gen_random_uuid(),
  score_id uuid not null references public.scores(id) on delete cascade,
  page int not null,
  drawer_name text not null default '',
  color text not null default '#ff5252',
  points jsonb not null default '[]',
  created_at timestamptz not null default now()
);
create table if not exists public.texts(
  id uuid primary key default gen_random_uuid(),
  score_id uuid not null references public.scores(id) on delete cascade,
  page int not null,
  drawer_name text not null default '',
  content text not null,
  x double precision not null,
  y double precision not null,
  size double precision not null default 24,
  color text not null default '#1c1c1c',
  created_at timestamptz not null default now()
);
create table if not exists public.layers(
  id uuid primary key default gen_random_uuid(),
  score_id uuid not null references public.scores(id) on delete cascade,
  owner_name text not null default '',
  layer_name text not null,
  file_path text not null,
  page_count int,
  created_at timestamptz not null default now()
);
create index if not exists strokes_page_idx on public.strokes(score_id, page);
create index if not exists texts_page_idx   on public.texts(score_id, page);
create index if not exists layers_score_idx on public.layers(score_id);

-- 3) Broadcast state (single row)
create table if not exists public.broadcast(
  id int primary key check (id=1),
  score_id uuid references public.scores(id) on delete set null,
  master_page int not null default 1
);
insert into public.broadcast(id) values (1) on conflict do nothing;

-- 4) Editor slots (max 2 concurrent leaders)
create table if not exists public.editors(
  slot int primary key check (slot in (1,2)),
  editor_name text not null default '',
  last_seen timestamptz not null default now() - interval '1 hour'
);
insert into public.editors(slot) values (1),(2) on conflict do nothing;

-- 5) Notice board
create table if not exists public.announcements(
  id uuid primary key default gen_random_uuid(),
  title text not null default '',
  body text not null default '',
  author text not null default '',
  pinned boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 6) RLS: public read; writes only via password-checked RPCs
do $$ declare tb text; begin
  foreach tb in array array['folders','scores','strokes','texts','layers',
                            'broadcast','editors','announcements'] loop
    execute format('alter table public.%I enable row level security', tb);
    begin
      execute format('create policy "read_%s" on public.%I for select
                      to anon, authenticated using (true)', tb, tb);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- 7) Realtime sync
do $$ declare tb text; begin
  foreach tb in array array['broadcast','strokes','texts','layers',
                            'editors','announcements'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', tb);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- 8) Storage bucket for PDFs (public read)
insert into storage.buckets(id, name, public) values ('scores','scores', true)
on conflict (id) do update set public = true;
drop policy if exists "score_read" on storage.objects;
drop policy if exists "score_ins"  on storage.objects;
drop policy if exists "score_del"  on storage.objects;
create policy "score_read" on storage.objects for select
  to anon, authenticated using (bucket_id='scores');
create policy "score_ins" on storage.objects for insert
  to anon, authenticated with check (bucket_id='scores');
create policy "score_del" on storage.objects for delete
  to anon, authenticated using (bucket_id='scores');

-- =====================================================
-- HELPER CHECKS
-- =====================================================
create or replace function public.fn_admin_ok(pw text) returns boolean
language sql stable security definer set search_path=public as
$$ select pw is not null and pw = (select admin_password from app_passwords limit 1) $$;

create or replace function public.fn_edit_ok(pw text) returns boolean
language sql stable security definer set search_path=public as
$$ select pw is not null and (pw = (select edit_password from app_passwords limit 1)
   or pw = (select admin_password from app_passwords limit 1)) $$;

-- =====================================================
-- AUTH / ADMIN RPCs
-- =====================================================
create or replace function public.verify_gate_pw(p_gate_pw text) returns boolean
language sql stable security definer set search_path=public as
$$ select p_gate_pw is not null and p_gate_pw = (select gate_password from app_passwords limit 1) $$;

create or replace function public.verify_admin_pw(p_admin_pw text) returns boolean
language sql stable security definer set search_path=public as
$$ select fn_admin_ok(p_admin_pw) $$;

create or replace function public.set_gate_password(p_admin_pw text, p_new text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  if p_new is null or length(p_new) < 4 then raise exception 'TOO_SHORT'; end if;
  update app_passwords set gate_password = p_new where id = 1;
end $$;

create or replace function public.set_edit_password(p_admin_pw text, p_new text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  if p_new is null or length(p_new) < 4 then raise exception 'TOO_SHORT'; end if;
  update app_passwords set edit_password = p_new where id = 1;
end $$;

create or replace function public.set_admin_password(p_admin_pw text, p_new text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  if p_new is null or length(p_new) < 4 then raise exception 'TOO_SHORT'; end if;
  update app_passwords set admin_password = p_new where id = 1;
end $$;

create or replace function public.clear_editors(p_admin_pw text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  update editors set editor_name = '', last_seen = now() - interval '1 hour';
end $$;

-- =====================================================
-- FILE MANAGEMENT RPCs (Chief)
-- =====================================================
create or replace function public.create_score_ex(
  p_admin_pw text, p_title text, p_file_path text,
  p_file_size bigint, p_page_count int, p_folder_id uuid
) returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  insert into scores(title,file_path,file_size,page_count,folder_id)
  values (p_title,p_file_path,p_file_size,p_page_count,p_folder_id)
  returning id into v;
  return v;
end $$;

create or replace function public.delete_score(p_admin_pw text, p_score_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  delete from strokes where score_id = p_score_id;
  delete from texts   where score_id = p_score_id;
  delete from layers  where score_id = p_score_id;
  delete from scores  where id = p_score_id;
end $$;

create or replace function public.rename_score(p_admin_pw text, p_score_id uuid, p_title text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  if p_title is null or length(trim(p_title)) = 0 then raise exception 'BAD_TITLE'; end if;
  update scores set title = left(trim(p_title),120) where id = p_score_id;
end $$;

create or replace function public.move_score_to(p_admin_pw text, p_score_id uuid, p_folder_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  update scores set folder_id = p_folder_id where id = p_score_id;
end $$;

create or replace function public.copy_score(p_admin_pw text, p_score_id uuid, p_folder_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  insert into scores(title,file_path,file_size,page_count,folder_id)
  select title || ' (copy)', file_path, file_size, page_count, p_folder_id
  from scores where id = p_score_id
  returning id into v;
  return v;
end $$;

create or replace function public.folder_create(p_admin_pw text, p_name text, p_parent_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  insert into folders(name,parent_id) values (left(trim(p_name),60),p_parent_id)
  returning id into v;
  return v;
end $$;

create or replace function public.folder_rename(p_admin_pw text, p_folder_id uuid, p_name text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  update folders set name = left(trim(p_name),60) where id = p_folder_id;
end $$;

create or replace function public.folder_delete(p_admin_pw text, p_folder_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  if exists(select 1 from folders where parent_id = p_folder_id)
     or exists(select 1 from scores where folder_id = p_folder_id) then
    raise exception 'FOLDER_NOT_EMPTY';
  end if;
  delete from folders where id = p_folder_id;
end $$;

create or replace function public.folder_move(p_admin_pw text, p_folder_id uuid, p_new_parent_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare bad boolean; begin
  if not fn_admin_ok(p_admin_pw) then raise exception 'WRONG_PASSWORD'; end if;
  if p_new_parent_id is not null then
    with recursive sub as (
      select id from folders where id = p_folder_id
      union all
      select f.id from folders f join sub s on f.parent_id = s.id
    )
    select exists(select 1 from sub where id = p_new_parent_id) into bad;
    if bad then raise exception 'BAD_TARGET'; end if;
  end if;
  update folders set parent_id = p_new_parent_id where id = p_folder_id;
end $$;

-- =====================================================
-- BROADCAST RPCs (editors)
-- =====================================================
create or replace function public.start_broadcast(p_edit_pw text, p_score_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  update broadcast set score_id = p_score_id, master_page = 1 where id = 1;
end $$;

create or replace function public.stop_broadcast(p_edit_pw text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  update broadcast set score_id = null, master_page = 1 where id = 1;
end $$;

create or replace function public.set_master_page(p_edit_pw text, p_page int)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  update broadcast set master_page = greatest(1,p_page) where id = 1;
end $$;

-- =====================================================
-- ANNOTATION RPCs (editors)
-- =====================================================
create or replace function public.add_stroke(
  p_edit_pw text, p_score_id uuid, p_page int, p_name text,
  p_color text, p_points jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  insert into strokes(score_id,page,drawer_name,color,points)
  values (p_score_id,p_page,coalesce(p_name,''),p_color,p_points)
  returning id into v;
  return v;
end $$;

create or replace function public.delete_stroke(p_edit_pw text, p_stroke_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  delete from strokes where id = p_stroke_id;
end $$;

create or replace function public.add_text(
  p_edit_pw text, p_score_id uuid, p_page int, p_name text,
  p_content text, p_x double precision, p_y double precision,
  p_size double precision, p_color text
) returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  insert into texts(score_id,page,drawer_name,content,x,y,size,color)
  values (p_score_id,p_page,coalesce(p_name,''),p_content,p_x,p_y,p_size,p_color)
  returning id into v;
  return v;
end $$;

create or replace function public.update_text(
  p_edit_pw text, p_text_id uuid,
  p_content text default null, p_size double precision default null,
  p_color text default null, p_x double precision default null,
  p_y double precision default null
) returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  update texts set
    content = coalesce(p_content, content),
    size    = coalesce(p_size, size),
    color   = coalesce(p_color, color),
    x       = coalesce(p_x, x),
    y       = coalesce(p_y, y)
  where id = p_text_id;
end $$;

create or replace function public.delete_text(p_edit_pw text, p_text_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  delete from texts where id = p_text_id;
end $$;

create or replace function public.add_layer(
  p_edit_pw text, p_score_id uuid, p_owner text,
  p_name text, p_file_path text, p_page_count int
) returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  insert into layers(score_id,owner_name,layer_name,file_path,page_count)
  values (p_score_id,coalesce(p_owner,''),p_name,p_file_path,p_page_count)
  returning id into v;
  return v;
end $$;

create or replace function public.delete_layer(
  p_edit_pw text, p_layer_id uuid,
  p_owner text default null, p_admin_pw text default null
) returns void language plpgsql security definer set search_path=public as $$
declare o text; begin
  select owner_name into o from layers where id = p_layer_id;
  if o is null then raise exception 'NOT_FOUND'; end if;
  if (fn_edit_ok(p_edit_pw) and o = coalesce(p_owner,'')) or fn_admin_ok(p_admin_pw) then
    delete from layers where id = p_layer_id;
    return;
  end if;
  raise exception 'WRONG_PASSWORD';
end $$;

-- =====================================================
-- EDITOR SLOT RPCs (editors)
-- =====================================================
create or replace function public.claim_editor(p_edit_pw text, p_name text)
returns int language plpgsql security definer set search_path=public as $$
declare s int; begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  select slot into s from editors
    where editor_name = coalesce(p_name,'') and editor_name <> ''
    order by slot limit 1;
  if s is not null then
    update editors set last_seen = now() where slot = s;
    return s;
  end if;
  select slot into s from editors
    where last_seen < now() - interval '45 seconds'
    order by slot limit 1;
  if s is null then raise exception 'EDITORS_FULL'; end if;
  update editors set editor_name = coalesce(p_name,''), last_seen = now() where slot = s;
  return s;
end $$;

create or replace function public.heartbeat_editor(p_edit_pw text, p_name text, p_slot int)
returns jsonb language plpgsql security definer set search_path=public as $$
declare m text; begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  update editors set last_seen = now()
    where slot = p_slot and editor_name = coalesce(p_name,'');
  if not found then raise exception 'SLOT_LOST'; end if;
  select editor_name into m from editors where slot = 1;
  return jsonb_build_object('slot',p_slot,'master',m);
end $$;

create or replace function public.release_editor(p_edit_pw text, p_name text, p_slot int)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  update editors set editor_name = '', last_seen = now() - interval '1 hour'
    where slot = p_slot and editor_name = coalesce(p_name,'');
end $$;

-- =====================================================
-- NOTICE BOARD RPCs (editors)
-- =====================================================
create or replace function public.add_announcement(
  p_edit_pw text, p_title text, p_body text, p_author text, p_pinned boolean default false
) returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  insert into announcements(title,body,author,pinned)
  values (coalesce(p_title,''),coalesce(p_body,''),coalesce(p_author,''),coalesce(p_pinned,false))
  returning id into v;
  return v;
end $$;

create or replace function public.update_announcement(
  p_edit_pw text, p_ann_id uuid, p_title text, p_body text, p_pinned boolean
) returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  update announcements set
    title = coalesce(p_title,title),
    body = coalesce(p_body,body),
    pinned = coalesce(p_pinned,pinned),
    updated_at = now()
  where id = p_ann_id;
end $$;

create or replace function public.delete_announcement(p_edit_pw text, p_ann_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not fn_edit_ok(p_edit_pw) then raise exception 'WRONG_PASSWORD'; end if;
  delete from announcements where id = p_ann_id;
end $$;

-- =====================================================
-- VERIFY: should return ~35 function names
-- =====================================================
select routine_name from information_schema.routines
where routine_schema = 'public' and routine_name not like 'fn_%'
order by routine_name;
