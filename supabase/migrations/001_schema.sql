-- Ricochet : schéma et règles d'accès.
-- Le dépôt est public et la clé publishable y figure : toute la sécurité repose sur ce fichier.
-- Sans le code d'équipe (jamais dans le dépôt), un compte ne voit rien et ne peut rien écrire.

create schema if not exists relais_private;
revoke all on schema relais_private from public, anon, authenticated;

-- Empreinte du code d'équipe, insérée à la main dans l'éditeur SQL. Inaccessible depuis l'API.
create table relais_private.team_code (
  id boolean primary key default true check (id),
  code_hash text not null
);
alter table relais_private.team_code enable row level security;

create table public.members (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  user_id uuid unique references auth.users (id) on delete set null,
  claimed_at timestamptz
);
insert into public.members (name) values ('Noé'), ('Alban'), ('Raphael'), ('Paul'), ('Louis');

create table public.prompts (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.members (id),
  recipient_id uuid not null references public.members (id),
  -- 14 000 : marge sous la limite de 14 336 caractères du lien claude://
  body text not null check (char_length(body) between 1 and 14000),
  summary text not null check (char_length(summary) between 1 and 80),
  status text not null default 'pending' check (status in ('pending', 'launched', 'refused')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  check (sender_id <> recipient_id)
);
create index prompts_recipient_idx on public.prompts (recipient_id, created_at desc);
create index prompts_sender_idx on public.prompts (sender_id, created_at desc);

-- Membre correspondant au compte connecté, ou null s'il n'a pas rejoint l'équipe.
create function public.current_member_id() returns uuid
language sql stable security definer set search_path = ''
as $$ select id from public.members where user_id = auth.uid() $$;

alter table public.members enable row level security;
alter table public.prompts enable row level security;

create policy "membres visibles par l'équipe" on public.members
  for select to authenticated using (public.current_member_id() is not null);

create policy "prompts visibles par expéditeur et destinataire" on public.prompts
  for select to authenticated
  using (public.current_member_id() in (sender_id, recipient_id));

create policy "envoi en son propre nom" on public.prompts
  for insert to authenticated
  with check (sender_id = public.current_member_id());

-- Droits minimaux : ni mise à jour ni suppression directes, statut et dates non modifiables.
revoke all on public.members, public.prompts from anon, authenticated;
grant select on public.members to authenticated;
grant select on public.prompts to authenticated;
grant insert (sender_id, recipient_id, body, summary) on public.prompts to authenticated;

-- Rejoindre l'équipe : un prénom ne peut être pris qu'une fois.
create function public.join_team(p_name text, p_code text) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_user uuid;
begin
  if auth.uid() is null then
    raise exception 'non_connecte';
  end if;
  if not exists (
    select 1 from relais_private.team_code
    where code_hash = encode(sha256(convert_to(p_code, 'UTF8')), 'hex')
  ) then
    raise exception 'code_invalide';
  end if;
  select id, user_id into v_id, v_user from public.members where name = p_name for update;
  if v_id is null then
    raise exception 'prenom_inconnu';
  end if;
  if v_user is not null and v_user <> auth.uid() then
    raise exception 'prenom_deja_pris';
  end if;
  update public.members set user_id = auth.uid(), claimed_at = now() where id = v_id;
  return v_id;
end;
$$;

-- Décision : seul le destinataire, et une seule fois.
create function public.decide_prompt(p_id uuid, p_status text) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_status not in ('launched', 'refused') then
    raise exception 'statut_invalide';
  end if;
  update public.prompts
    set status = p_status, decided_at = now()
    where id = p_id
      and recipient_id = public.current_member_id()
      and status = 'pending';
  if not found then
    raise exception 'decision_impossible';
  end if;
end;
$$;

revoke all on function public.current_member_id() from public, anon;
revoke all on function public.join_team(text, text) from public, anon;
revoke all on function public.decide_prompt(uuid, text) from public, anon;
grant execute on function public.current_member_id() to authenticated;
grant execute on function public.join_team(text, text) to authenticated;
grant execute on function public.decide_prompt(uuid, text) to authenticated;

alter publication supabase_realtime add table public.prompts;
