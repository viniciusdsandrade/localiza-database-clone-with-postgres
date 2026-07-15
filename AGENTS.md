# AGENTS.md

## Visao geral do projeto

Este repositorio implementa um modelo de dados de referencia para uma plataforma
de locacao e gestao de veiculos no porte e com caracteristicas publicamente
observaveis da Localiza.

O projeto nao reproduz, nem deve alegar reproduzir, bancos, schemas, DDLs,
nomes de tabelas ou fronteiras transacionais proprietarias da Localiza. Trate
toda associacao com a empresa como contexto de dominio baseado em informacoes
publicas. Ao documentar decisoes, diferencie claramente:

- `FATO PUBLICO`: sustentado por uma fonte publica verificavel;
- `INFERENCIA`: consequencia arquitetural plausivel, sem confirmacao interna;
- `DECISAO DE PROJETO`: escolha adotada por este repositorio.

O objetivo pratico e disponibilizar DDLs executaveis e documentados para
PostgreSQL e MySQL, preservando a mesma semantica de dominio nos dois motores e
explicitando as diferencas inevitaveis entre eles.

## Artefatos principais

Os entregaveis esperados na raiz sao:

- `rental_platform_postgresql.sql`: bootstrap completo para PostgreSQL;
- `rental_platform_mysql.sql`: bootstrap completo para Oracle MySQL 8.x;
- `README_rental_platform_ddl.md`: requisitos, execucao, limitacoes e exemplos;
- `rental_platform_schema_manifest.csv`: inventario logico de schemas, tabelas e
  relacionamentos.

Nao declare contagens de tabelas, foreign keys, triggers ou testes como atuais
sem recalcula-las a partir dos arquivos presentes e, quando aplicavel, de uma
execucao limpa no banco correspondente.

## Arquitetura de dados

O modelo logico e organizado nos seguintes bounded contexts:

- `org`
- `party`
- `catalog`
- `fleet`
- `availability`
- `pricing`
- `reservation`
- `rental`
- `inspection`
- `billing`
- `traffic`
- `claim`
- `maintenance`
- `telematics`
- `loyalty`
- `corporate`
- `fleet_mgmt`
- `used_car`
- `privacy`
- `integration`

No PostgreSQL, represente os contextos com schemas. No MySQL, que nao oferece
namespaces equivalentes dentro do mesmo database, use prefixos de tabela
consistentes, por exemplo `fleet_vehicle` e `billing_charge`.

Mantenha o nucleo OLTP separado de dados brutos de telemetria, conteudo binario
de documentos e fotos e cargas analiticas. No OLTP, armazene apenas metadados,
referencias, indices e resumos necessarios a operacao.

## Regras de modelagem nao negociaveis

### Identidade, tempo e dinheiro

- Use `uuid` como chave tecnica no PostgreSQL e uma representacao UUID
  documentada e consistente no MySQL.
- Mantenha identificadores visiveis, como numeros de reserva, contrato, fatura e
  frota, como chaves de negocio separadas.
- Nunca use CPF, CNPJ, placa, chassi, CNH ou e-mail como chave primaria.
- Use `timestamptz` para instantes no PostgreSQL e preserve explicitamente a
  semantica UTC/fuso equivalente no MySQL.
- Modele periodos como intervalos semiabertos `[inicio, fim)`.
- Use `numeric(19,4)` ou `decimal(19,4)` para valores monetarios e uma coluna
  `currency_code char(3)`. Nunca use tipos de ponto flutuante para dinheiro.
- Agregados mutaveis devem possuir auditoria minima (`created_at`, `created_by`,
  `updated_at`, `updated_by`) e controle otimista por `row_version`, quando
  aplicavel.

### Reserva, contrato e frota

- A reserva compromete capacidade de um grupo de veiculos; ela nao deve exigir
  a atribuicao antecipada de um veiculo exato.
- O veiculo deve ser atribuido na retirada ou preparacao da retirada e precisa
  pertencer ao grupo reservado ou a um upgrade permitido.
- Use um calendario unificado do veiculo para locacao, manutencao, transferencia,
  limpeza, inspecao, preparacao de venda e bloqueios manuais.
- Impeca ocupacoes conflitantes do mesmo veiculo no banco. No PostgreSQL, prefira
  `tstzrange` com `EXCLUDE USING gist`. No MySQL, documente e teste o protocolo
  transacional com linha-guarda, `SELECT ... FOR UPDATE` e trigger de defesa.
- Nao sobrescreva a atribuicao anterior em uma troca de veiculo; encerre o
  intervalo existente e crie uma nova atribuicao sequencial.
- Modele cliente, usuario corporativo, representante, condutores, pagador e
  responsavel pela reserva como participantes com papeis, pois podem ser pessoas
  ou organizacoes diferentes.
- Separe estado operacional do veiculo, estado de ciclo de vida e restricoes.
  Nao crie um enum unico com combinacoes desses eixos.

### Precificacao, cobranca e fidelidade

- Versione planos e regras tarifarias por vigencia. Versoes publicadas sao
  imutaveis e nao podem possuir vigencias conflitantes para o mesmo plano.
- Preserve snapshots distintos para preco cotado, reservado, contratado e
  efetivamente cobrado.
- Represente cobrancas, pagamentos e pontos como ledgers auditaveis e
  idempotentes. Lancamentos publicados nao sao atualizados nem excluidos;
  correcoes usam estorno, reversao ou lancamento compensatorio.
- O saldo de fidelidade e uma projecao dos lancamentos, nao a fonte de verdade.
- Eventos tardios, como multa, pedagio ou dano reavaliado, geram cobranca e
  documento suplementares sem reabrir ou reescrever o contrato encerrado.
- Toda integracao financeira ou callback externo deve possuir chave de
  idempotencia e referencia externa unica apropriada.

### Privacidade e seguranca

- Segregue PII e armazene identificadores pesquisaveis de baixo espaco, como
  CPF/CNPJ, com HMAC de um valor normalizado; hash simples nao e protecao
  suficiente contra enumeracao.
- Criptografe o valor original ou mantenha-o em um cofre de PII. Nao exponha
  identificadores sensiveis em logs, fixtures ou payloads de auditoria.
- Armazene apenas tokens e metadados permitidos de cartoes. Nunca armazene PAN
  completo, CVV, trilha magnetica ou PIN.
- Diferencie base legal de consentimento, implemente retencao e `legal_hold` e
  nao confunda pseudonimizacao reversivel com anonimizacao.
- Audite acessos administrativos a dados pessoais sensiveis.

### Integracao e historico

- Use `integration.outbox_event` na mesma transacao da alteracao do agregado.
- Consumidores devem registrar mensagens processadas em inbox para garantir
  idempotencia.
- Tabelas de historico, auditoria e ledger sao append-only. Nao introduza
  `UPDATE` ou `DELETE` destrutivo nesses registros.
- Colunas `current_status` e outros campos `current_*` sao projecoes para leitura;
  o historico correspondente permanece autoritativo.

## Convencoes dos scripts SQL

- Scripts precisam ser reexecutaveis em uma instancia limpa conforme o fluxo
  documentado. Nao esconda pre-condicoes manuais.
- Ordene a criacao de schemas, tabelas e constraints de forma deterministica.
- Nomeie PKs, FKs, uniques, checks, indices, triggers e procedures de forma
  estavel e legivel, respeitando os limites de identificadores de cada motor.
- Nao enfraqueca uma regra apenas para tornar os dialetos textualmente iguais.
  Implemente a garantia mais forte disponivel em cada engine e documente a
  diferenca operacional.
- No PostgreSQL, mantenha dependencias de `pgcrypto` e `btree_gist` explicitas.
- No MySQL, direcione o arquivo ao Oracle MySQL 8.x com InnoDB e `utf8mb4`.
  Compatibilidade com MariaDB e evidencia adicional, nao substitui a validacao
  na versao declarada do Oracle MySQL.
- Delimitadores, procedures e triggers do MySQL devem funcionar quando o arquivo
  for executado integralmente pelo cliente `mysql`.
- Nao use `json`/`jsonb` para esconder relacionamentos essenciais. Reserve-os
  para payloads externos, snapshots, metadados e expressoes versionadas.
- Evite EAV generico. Normalize dimensoes e relacionamentos centrais.
- Nao particione tabelas preventivamente; use particionamento apenas com volume,
  retencao e padrao de acesso documentados.

## Validacao

Para qualquer alteracao de DDL, execute a verificacao mais barata que prove a
mudanca e amplie para bootstrap real quando houver suporte local. Registre a
versao exata do servidor usado.

O gate ideal inclui:

1. analise estatica dos dois scripts e verificacao do manifest;
2. bootstrap completo em databases limpos;
3. contagem recalculada de schemas, tabelas, FKs, indices, triggers e procedures;
4. testes positivos e negativos das invariantes afetadas;
5. nova execucao a partir do zero para detectar dependencias de ordem;
6. comparacao entre documentacao, manifest e objetos realmente criados.

Ao tocar nas regras correspondentes, cubra pelo menos estes riscos:

- rejeicao de intervalos sobrepostos e aceitacao de intervalos adjacentes;
- concorrencia no limite da capacidade por grupo;
- liberacao idempotente de hold expirado ou reserva cancelada;
- bloqueio de manutencao sobreposta a uma locacao;
- rejeicao de versoes tarifarias publicadas sobrepostas;
- imutabilidade de cobrancas contabilizadas e do ledger de pontos;
- deduplicacao de pagamento, multa, pedagio, inbox e outbox;
- reversao e relancamento sem alterar o registro original;
- preservacao do historico de placa, odometro, grupo e atribuicao do veiculo;
- retencao ou `legal_hold` impedindo exclusao indevida de dados pessoais.

Nunca afirme que um script foi executado em PostgreSQL, Oracle MySQL ou MariaDB
sem evidencia da execucao atual. Se um motor nao estiver disponivel, reporte a
limitacao com precisao e nao transforme validacao estatica em smoke test real.

## Forma de trabalhar neste repositorio

- Leia este arquivo, a documentacao e o manifest antes de alterar DDLs.
- Preserve mudancas existentes e mantenha cada diff restrito ao pedido atual.
- Prefira mudancas pequenas, deterministicas e identicas em semantica nos dois
  dialetos.
- Ao adicionar ou remover um objeto logico, atualize no mesmo trabalho os dois
  DDLs, o manifest e a documentacao afetada, salvo quando o pedido delimitar
  explicitamente outro escopo.
- Nao invente fatos sobre sistemas internos da Localiza. Fontes atuais e
  instaveis devem ser verificadas em documentacao primaria antes de serem
  citadas.
- Nao faca refactors, formatacao ampla, renomes ou upgrades fora do escopo.
- Antes de concluir, revise `git diff`, rode `git diff --check` e informe arquivos
  alterados, comandos de validacao e limitacoes remanescentes.
- Commit, push e deploy somente quando solicitados. Antes de publicar, confirme
  branch, arquivos staged e alinhamento com a remota.

## Fora do escopo do nucleo

Nao absorva no modelo operacional folha de pagamento, recrutamento,
contabilidade geral completa, tesouraria corporativa completa, compras
administrativas, patrimonio nao veicular, CRM completo, campanhas de marketing
completas, blobs de documentos/fotos, telemetria bruta ou o data warehouse
inteiro. Integre esses sistemas por referencias e eventos quando necessario.
