# Almoxarifado NorteShopping

Controle de estoque das peças de manutenção do NorteShopping (identidade ALLOS).
App em **um único arquivo HTML** ([index.html](index.html)) — funciona aberto
direto no navegador ou publicado como site estático.

Os dados ficam **na nuvem (Supabase)**, compartilhados pela equipe: cada pessoa
entra com o próprio e-mail e senha, todos veem e alteram o mesmo estoque, e toda
mudança fica registrada na **Auditoria** com o e-mail de quem fez.

## Backend

Projeto Supabase: **`waldiney1980@gmail.com's Project`** (`mhqhbnfbfrfsckhcvzis`),
o mesmo do HidroLuz e do controle financeiro.

- URL: `https://mhqhbnfbfrfsckhcvzis.supabase.co`
- Chave publicável: `sb_publishable_cz6stQiD91vUY50hapD3Qw_Non3Y2ea`

Tabelas com prefixo `alx_` (não colidem com os outros apps):

| Tabela | Conteúdo |
|---|---|
| `alx_itens` | os itens do estoque (código único, quantidades, localização, fornecedor…) |
| `alx_movs` | histórico de entradas e saídas |
| `alx_compras` | solicitações de compra (Pendente → Comprado → Recebido) |
| `alx_equipamentos` | cadastro de equipamento/destino que alimenta o campo da saída (nome único por grupo) |
| `alx_audit` | trilha de auditoria: quem criou/alterou/excluiu cada registro |

Todas com **RLS ligado** e política para usuários autenticados (dados
compartilhados pela equipe). As quatro primeiras têm o **trigger `trg_guard_*`**
que descarta escrita atrasada, no padrão do HidroLuz.

A **auditoria é preenchida por trigger no servidor** (`alx_audit_fn`,
`security definer`): o app não consegue gravar nem alterar a trilha pela API —
só ler. Regravações sem mudança real não geram registro. Migrations aplicadas:
`almoxarifado_norteshopping_tabelas` e `almoxarifado_auditoria`. O SQL completo
está em [db/supabase.sql](db/supabase.sql).

## Como o app sincroniza

- Ao entrar, o app baixa as tabelas inteiras (paginado de 1000 em 1000).
- Cada alteração grava **apenas a diferença**: exclusões primeiro (o código do
  item é único no banco), depois upserts em lote com `updated_at` crescente.
- Se a rede falhar, o app avisa, mantém as alterações pendentes e tenta de novo
  a cada 15 segundos; ao fechar a aba com pendências, o navegador alerta.
- Ao voltar o foco para a aba (sem formulário aberto e sem pendências), o app
  recarrega da nuvem — assim uma máquina enxerga o que a outra lançou.

## Grupos (multi-shopping)

Cada **grupo = um shopping**, com itens, movimentações, compras e auditoria
próprios, **isolados por RLS no banco** (`grupo_id = alx_meu_grupo()` em todas
as políticas — um grupo não enxerga o outro nem chamando a API diretamente).

- Na primeira entrada, o usuário **cria um grupo** (nome do shopping) ou
  **entra num grupo existente com o código de acesso** (6 caracteres, exibido
  em **Dados → Grupo (shopping)**).
- O nome de equipamento também é único **por grupo**.
- O código de item é único **por grupo**; a lista oficial pode ser carregada
  em cada grupo.
- Tabelas: `alx_grupos` e `alx_membros`; RPCs `alx_criar_grupo`,
  `alx_entrar_grupo` e `alx_meu_grupo_info` (só para autenticados).
- Migration: `almoxarifado_grupos_multi_shopping`. Os dados anteriores viraram
  o grupo **NorteShopping**, com os usuários da época como membros.

## Contas e auditoria

Mesmo cadastro de usuários do HidroLuz (mesmo projeto Supabase). Conta nova pode
ser criada na própria tela de login. O **operador** exibido nas movimentações é
um apelido local (clique no nome no topo para trocar); a **Auditoria** registra
sempre o e-mail autenticado de verdade, com o antes/depois de cada campo.

## Publicação (GitHub Pages)

O site é estático — o repositório publicado no GitHub Pages serve o
`index.html` direto. Roteiro:

1. Criar o repositório **público** `almoxarifado` em <https://github.com/new>
   (conta `waldiney1980-source`), sem README inicial.
2. Enviar o código:

   ```bash
   cd /Users/eduarda/Documents/almoxarifado
   git remote add origin git@github.com:waldiney1980-source/almoxarifado.git
   git push -u origin main
   ```

3. No repositório: **Settings → Pages → Source: Deploy from a branch →
   Branch: `main` / `(root)` → Save**.
4. Em ~2 minutos o app fica em
   `https://waldiney1980-source.github.io/almoxarifado/`.

### ⚠️ Hoje o Pages publica do branch `gh-pages`, não do `main`

Na configuração atual, o **Settings → Pages** deste repositório aponta para o
branch **`gh-pages`**. Só `git push origin main` **não publica nada** — o site
continua na versão anterior e nenhum build é enfileirado (nem com commit vazio).

Enquanto for assim, publicar é:

```bash
git push origin main                  # guarda o código
git push origin main:gh-pages         # é ISTO que publica
```

Para simplificar de vez, mude uma única vez em **Settings → Pages → Source**
para o branch **`main` / `(root)`** — daí o `git push origin main` volta a
publicar sozinho, e o branch `gh-pages` pode ser esquecido.

Um workflow do Actions **não resolve** sem essa mudança: o environment
`github-pages` só aceita deploy vindo de `gh-pages` e recusa o `main` com
*“Branch main is not allowed to deploy to github-pages due to environment
protection rules”*.

A chave no código é a **publicável** (feita para ficar exposta); quem não tem
conta não lê nada — o RLS bloqueia.

## Migrar os lançamentos da versão antiga (LocalStorage)

Se houver lançamentos feitos na versão antiga em alguma máquina:

1. Abra o app novo naquela máquina e entre — se a nuvem estiver vazia, a base
   local sobe sozinha; **ou**
2. na versão antiga, use **Dados → Exportar backup**, e no app novo use
   **Dados → Importar backup** (substitui o que estiver na nuvem).

## Arquivos

- [index.html](index.html) — o sistema completo
- [manual.html](manual.html) — manual do usuário em slides (ainda descreve a
  versão LocalStorage; a seção "Onde os dados ficam guardados" ficou desatualizada)
- [db/supabase.sql](db/supabase.sql) — esquema do banco, para recriar em outro projeto

O projeto nasceu como artifacts no Claude (versão LocalStorage, sem nuvem);
esses artifacts foram apagados em 29/07/2026 — este repositório é a única fonte.
