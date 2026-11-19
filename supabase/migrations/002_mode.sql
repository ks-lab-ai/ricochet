-- Mode de lancement choisi par l'expéditeur : Claude (conversation) ou Claude Code.
-- Les anciennes versions de l'app n'envoient pas ce champ : « chat » par défaut.
alter table public.prompts
  add column if not exists mode text not null default 'chat' check (mode in ('chat', 'code'));
grant insert (mode) on public.prompts to authenticated;
