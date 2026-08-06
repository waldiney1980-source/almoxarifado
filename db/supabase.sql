-- Almoxarifado NorteShopping — esquema no Supabase (Postgres).
-- Já aplicado no projeto mhqhbnfbfrfsckhcvzis via migration:
--   almoxarifado_norteshopping_tabelas
-- Este arquivo reproduz o resultado, para recriar em outro projeto.

create table if not exists public.alx_itens (
  id             uuid primary key,
  codigo         text not null default '',
  descricao      text not null default '',
  categoria      text not null default '',
  unidade        text not null default 'UN',
  atual          double precision not null default 0,
  min            double precision not null default 0,
  max            double precision not null default 0,
  valor_unit     double precision not null default 0,
  prateleira     text not null default '',
  coluna         text not null default '',
  gaveta         text not null default '',
  fornecedor     text not null default '',
  lead_time      integer not null default 0,
  ultima_compra  text not null default '',
  updated_at     bigint not null default 0,
  owner_id       uuid not null default auth.uid() references auth.users(id) on delete cascade
);

create table if not exists public.alx_movs (
  id       uuid primary key,
  type     text not null check (type in ('entrada','saida')),
  item_id  uuid not null,               -- referência lógica a alx_itens.id (item pode ser excluído; o histórico permanece)
  qty      double precision not null default 0,
  date     text not null default '',    -- ISO yyyy-mm-dd
  obs      text not null default '',
  equip    text not null default '',
  usuario  text not null default '',
  ts       bigint not null default 0,
  updated_at bigint not null default 0,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade
);

create table if not exists public.alx_compras (
  id          uuid primary key,
  item_id     uuid not null,
  qtd         double precision not null default 0,
  status      text not null default 'Pendente' check (status in ('Pendente','Comprado','Recebido')),
  criada_em   text not null default '',
  recebida_em text not null default '',
  updated_at  bigint not null default 0,
  owner_id    uuid not null default auth.uid() references auth.users(id) on delete cascade
);

-- Cadastro de Equipamento / destino (migration: almoxarifado_equipamentos_destinos).
-- Alimenta a lista do campo "Equipamento / destino" da saída. A movimentação continua
-- gravando o NOME em alx_movs.equip — o cadastro só padroniza a digitação.
create table if not exists public.alx_equipamentos (
  id         uuid primary key,
  nome       text not null default '',
  tag        text not null default '',
  tipo       text not null default '',
  local      text not null default '',
  obs        text not null default '',
  ativo      boolean not null default true,
  updated_at bigint not null default 0,
  owner_id   uuid not null default auth.uid() references auth.users(id) on delete cascade
  -- grupo_id uuid references public.alx_grupos(id) on delete cascade  (ver bloco de grupos abaixo)
);
create unique index if not exists idx_alx_equip_nome  on public.alx_equipamentos(grupo_id, lower(nome));
create index        if not exists idx_alx_equip_grupo on public.alx_equipamentos(grupo_id);

create index if not exists idx_alx_movs_item    on public.alx_movs(item_id);
create index if not exists idx_alx_movs_date    on public.alx_movs(date);
create index if not exists idx_alx_compras_item on public.alx_compras(item_id);
create unique index if not exists idx_alx_itens_codigo on public.alx_itens(lower(codigo));

alter table public.alx_itens        enable row level security;
alter table public.alx_movs         enable row level security;
alter table public.alx_compras      enable row level security;
alter table public.alx_equipamentos enable row level security;

-- Escrita atrasada nunca sobrescreve a mais nova (mesmo padrão do HidroLuz).
create or replace function public.alx_guard_updated_at()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return old;
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['alx_itens','alx_movs','alx_compras','alx_equipamentos'] loop
    execute format('drop trigger if exists %I on public.%I', 'trg_guard_' || t, t);
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.alx_guard_updated_at()',
      'trg_guard_' || t, t);

    -- Dados compartilhados pela equipe do almoxarifado. Para isolar por usuário,
    -- troque `true` por `owner_id = auth.uid()` nas duas cláusulas.
    execute format('drop policy if exists %I on public.%I', t || '_equipe_all', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (true) with check (true)',
      t || '_equipe_all', t);
  end loop;
end $$;

-- ============================================================================
-- Trilha de auditoria (migration: almoxarifado_auditoria)
-- Cada criação/alteração/exclusão nas tabelas alx_* gera um registro com o
-- usuário autenticado. Preenchida por trigger; pela API é somente leitura.
-- ============================================================================

create table if not exists public.alx_audit (
  id         bigint generated always as identity primary key,
  tabela     text not null,
  acao       text not null check (acao in ('criou','alterou','excluiu')),
  row_id     uuid not null,
  usuario_id uuid,
  email      text not null default '',
  dados      jsonb,          -- estado novo (ou o excluído)
  antes      jsonb,          -- estado anterior (apenas em alterações)
  criado_em  timestamptz not null default now()
);

create index if not exists idx_alx_audit_criado  on public.alx_audit(criado_em desc);
create index if not exists idx_alx_audit_email   on public.alx_audit(email);
create index if not exists idx_alx_audit_tabela  on public.alx_audit(tabela);

alter table public.alx_audit enable row level security;

drop policy if exists alx_audit_leitura on public.alx_audit;
create policy alx_audit_leitura on public.alx_audit
  for select to authenticated using (true);

create or replace function public.alx_audit_fn()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := coalesce(nullif(auth.jwt()->>'email',''), '');
begin
  if tg_op = 'INSERT' then
    insert into public.alx_audit (tabela, acao, row_id, usuario_id, email, dados)
    values (tg_table_name, 'criou', new.id, auth.uid(), v_email, to_jsonb(new) - 'owner_id');
    return new;
  elsif tg_op = 'UPDATE' then
    if (to_jsonb(new) - 'updated_at' - 'owner_id') = (to_jsonb(old) - 'updated_at' - 'owner_id') then
      return new;
    end if;
    insert into public.alx_audit (tabela, acao, row_id, usuario_id, email, dados, antes)
    values (tg_table_name, 'alterou', new.id, auth.uid(), v_email,
            to_jsonb(new) - 'owner_id', to_jsonb(old) - 'owner_id');
    return new;
  else
    insert into public.alx_audit (tabela, acao, row_id, usuario_id, email, dados)
    values (tg_table_name, 'excluiu', old.id, auth.uid(), v_email, to_jsonb(old) - 'owner_id');
    return old;
  end if;
end $$;

revoke execute on function public.alx_audit_fn() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['alx_itens','alx_movs','alx_compras','alx_equipamentos'] loop
    execute format('drop trigger if exists %I on public.%I', 'trg_audit_' || t, t);
    execute format(
      'create trigger %I after insert or update or delete on public.%I for each row execute function public.alx_audit_fn()',
      'trg_audit_' || t, t);
  end loop;
end $$;

-- ============================================================================
-- Grupos / multi-shopping (migration: almoxarifado_grupos_multi_shopping)
-- Cada grupo (shopping) tem seus próprios dados, isolados por RLS. Entrar num
-- grupo exige o código de acesso. Os dados pré-existentes foram atribuídos ao
-- grupo NorteShopping, com os usuários da época como membros.
-- Ver a migration no projeto para o SQL completo — resumo do que existe:
--   * tabelas alx_grupos (nome, codigo único) e alx_membros (user_id → grupo_id)
--   * coluna grupo_id em alx_itens, alx_movs, alx_compras, alx_equipamentos e alx_audit
--   * código de item único POR GRUPO: unique (grupo_id, lower(codigo))
--   * fn alx_meu_grupo() (security definer) usada nas políticas
--   * trigger trg_grupo_* carimba o grupo em inserts e o congela em updates
--   * políticas: using/with check (grupo_id = alx_meu_grupo()) nas 3 tabelas;
--     alx_audit somente leitura filtrada por grupo
--   * nome de equipamento único POR GRUPO: unique (grupo_id, lower(nome))
--   * RPCs (execute só para authenticated): alx_criar_grupo(nome),
--     alx_entrar_grupo(codigo), alx_meu_grupo_info()


-- ============================================================================
-- Foto e prateleira vermelha (migration: almoxarifado_foto_e_prateleira_vermelha)
--   * alx_itens.foto text — caminho no bucket privado alx-fotos (<grupo_id>/<item_id>.jpg)
--   * alx_itens.prateleira_vermelha boolean — item que não pode faltar
--   * bucket storage alx-fotos (privado, 3 MB, jpeg/png/webp) com políticas
--     select/insert/update/delete restritas à pasta do grupo do usuário
--     ((storage.foldername(name))[1] = alx_meu_grupo()::text)
-- ============================================================================

-- ============================================================================
-- Fluxo de compras (migration: almoxarifado_compras_status_e_fornecedor)
--   * alx_compras.fornecedor text, preco double precision, obs text
--   * alx_compras.foto text — foto do recebimento (NF/material), bucket alx-fotos
--     em <grupo_id>/recebimentos/<compra_id>.jpg (migration almoxarifado_foto_recebimento)
--   * status: Solicitada → Aprovada → Em Cotação → Comprada → Em Transporte → Recebida
--     (antigos Pendente/Comprado/Recebido migrados; o app também normaliza na leitura)
--   * a solicitação automática por estoque mínimo foi removida do app: compra
--     nasce no botão Comprar e o estoque só muda no Recebimento
-- ============================================================================
