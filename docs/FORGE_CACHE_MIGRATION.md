# XT Prison — cache e instalação Forge

Implementado em 01/10/2026. **Homologação no FiveM pendente.** Alterações de runtime restritas ao XT Prison; nenhum banco real foi alterado durante esta execução.

## Índice

- [Cache do personagem](#cache-do-personagem)
- [Estado compartilhado da prisão](#estado-compartilhado-da-prisão)
- [Banco e configurações](#banco-e-configurações)
- [Integrações](#integrações)
- [Validação e teste no servidor](#validação-e-teste-no-servidor)
- [Limites desta etapa](#limites-desta-etapa)

## Cache do personagem

- `bridge/cache.lua` substitui todos os acessos diretos a state bags do recurso por `pr_lib.cache`.
- Servidor: `xt-prison:character:<identificador>` guarda pena, sentença e identificador; `xt-prison:binding:<source>` relaciona conexão e personagem. O identificador é obtido por `pr_lib.framework.GetIdentifier`, nunca enviado pelo cliente para selecionar o personagem.
- A identificação e a escrita do metadata `injail` continuam passando pela framework do PR Bridge. QBX continua responsável pelo PlayerData; não foi criada outra cópia de PlayerData, nem alterado o formato dos caches internos do QBX/Forge Core.
- Os dados da prisão são uma extensão de cache vinculada ao personagem, não uma inserção em chaves internas não documentadas da framework. `SetPlayerMetadata` mantém a relação com os dados da framework.
- No cliente, `xt-prison:self` é a visão local. A escrita local não replica pena ao servidor. O snapshot retorna somente os dados do próprio jogador; atualizações pessoais são direcionadas ao respectivo source, nunca broadcast.
- Revisões rejeitam pacotes antigos. Respostas de snapshot iniciadas antes de logout são descartadas; snapshots reidratam o cache após entrada/reinício.
- Disconnect/logout salvam a pena antes da limpeza; há fallback ao identificador já associado quando a framework removeu o jogador. A limpeza confere o identificador para não apagar uma sessão substituta após uma espera no banco.
- Cooldown de consulta de pena usa cache vinculado ao source, com TTL de 5 segundos.
- O comando de soltura zera a pena no servidor antes do callback de saída. A saída consulta o snapshot antes de devolver itens. Não há espera infinita por alteração de state bag.

## Estado compartilhado da prisão

- `xt-prison:world`: contagem policial, alarme e terminais. Eventos do próprio recurso sincronizam o cache entre servidor e clientes; callbacks de snapshot usam PR Bridge.
- É um estado compartilhado da prisão, portanto seus deltas são broadcast. Dados pessoais e configurações completas não fazem parte desse broadcast de mundo.
- Configurações ficam em `xt-prison:settings`, com o transporte existente `settingsUpdated`; a inicialização também anuncia as configurações carregadas.
- Reservas de terminais são liberadas quando o jogador sai. Identificadores inválidos, flags de tipo incorreto e tentativas de assumir terminal ocupado por outro jogador são recusados.
- Reset de alarmes/portões e cooldowns existentes foram preservados. A integração existente com doorlock não foi migrada nesta etapa.
- A carga e a edição das configurações recriam o cache dos terminais; timers de uma configuração anterior não podem modificar terminais da nova configuração.

## Banco e configurações

- `modules/server/db.lua` é o ponto único de criação das tabelas `xt_prison`, `xt_prison_items` e `xt_prison_settings`.
- Inicialização via `pr_lib.database.ready`; cada criação é verificada no schema atual. Falhas são registradas e não marcam o instalador como pronto.
- `awaitReady()` fornece espera limitada e erro explícito. O armazenamento de configurações e a carga/salvamento da pena aguardam esse contrato.
- A tabela de configurações utiliza `id VARCHAR(50)` como chave primária, `data LONGTEXT` e `updated_at TIMESTAMP`. A linha utilizada é `id = 'global'`.
- Em uma instalação sem configurações, os padrões normalizados são inseridos. Salvamento consulta a linha novamente e confirma o conteúdo gravado.
- JSON inválido ou banco indisponível bloqueiam o salvamento do armazenamento; os dados existentes são preservados. A interface pode exibir padrões como fallback com erro registrado no console.
- O modo `file` continua disponível somente por escolha explícita na convar `xt-prison:settingsStorage`; preserva backup e conferência de escrita.
- Instalação antiga sem `xt_prison.sentence` recebe a coluna adicional. Importação de `jailtime` legado usa `INSERT IGNORE`, sem sobrescrever penas já existentes.
- Removida a exclusão automática da coluna `jailtime` da framework. Esta etapa não apaga colunas nem dados existentes.
- A estrutura foi conferida pelo código e por mocks; não houve conexão a MariaDB, execução de SQL real ou restart do FXServer nesta revisão.

## Integrações

### Forge Core e correção da confirmação silenciosa

Correção em 01/10/2026: o callback do formulário expirava no prazo padrão de 10 segundos, descartando confirmações demoradas sem informar o motivo. Formulário agora usa `awaitClient` com 120 segundos; entrada/saída usam 45 segundos, incluindo fades e carregamento do cenário. Cancelamento voluntário continua sem erro. Falhas de callback/entrada são notificadas e registradas com motivo.

`server/sv_actions.lua` fornece um único fluxo para comandos, lista e integrações. Persiste a sentença antes da entrada, bloqueia ações concorrentes por personagem e restaura pena/metadata anteriores quando a entrada falha. Uma tentativa frustrada não cai mais num ramo que apenas alterava o tempo sem tentar o teleporte novamente. A confirmação própria do cliente consulta a pena definida pelo servidor, sem criar outra pena. Itens são confiscados depois do posicionamento bem-sucedido. As opções configuradas de remover emprego e uniforme continuam sendo respeitadas.

Novos exports **de servidor**, destinados a scripts confiáveis:

```lua
local ok, reason = exports['xt-prison']:JailPlayer(source, { amount = 5, unit = 'minutes', clock = 'real' })
local ok, reason = exports['xt-prison']:ReleasePlayer(source)
local status = exports['xt-prison']:GetPrisonStatus(source)
```

O Forge Core não chama esses exports diretamente: usa `pr_lib.load('@pr_bridge/bridge/prison/server')`. Esse adaptador opcional concentra acesso ao provedor, verifica o recurso iniciado e trata indisponibilidade. O novo serviço do Forge valida no servidor a mesma autorização administrativa usada na gestão de jogadores. Os callbacks novos também integram o bloqueio administrativo existente do Forge.

- Gestão de jogadores: dados principais exibem estado/tempo/relógio/pena; ações diretas **Definir prisão** e **Retirar da prisão**, somente com o provedor ativo.
- F9: mostra os dados da própria pena quando o jogador está preso e o provedor está ativo. Não oferece ações administrativas.
- Sem XT Prison iniciado: dados e ações são omitidos, sem nova dependência obrigatória de inicialização.
- Textos novos do Forge nas duas locales existentes; mensagem de falha do XT Prison nas seis locales existentes.
- Callback administrativo do Forge aguarda 60 segundos, sem o prazo genérico de 10 segundos para uma operação que inclui streaming.

Validado com mocks e o callback real do PR Bridge: formulário de 25 segundos antes/depois; entrada real do módulo cliente acima de 12 segundos; falha de emprego/entrada; rollback; permissões; provedor parado; menus F9/gestão efetivamente carregados dos arquivos.

```lua
-- Servidor: consulta do próprio recurso por source.
local prison = exports['xt-prison']:GetPrisonCache(source)
local remaining = prison and prison.jailTime or 0

-- Servidor: export existente para alteração autorizada pela integração.
exports['xt-prison']:SetJailTime(source, 15)

-- Cliente: sem parâmetro, retorna a visão do próprio personagem.
local prison = exports['xt-prison']:GetPrisonCache()
```

Integrações externas que ainda leem `Player(...).state.jailTime`, `jailSentence` ou globals da prisão precisam migrar seus acessos. Elas não foram modificadas nesta etapa. Os eventos de compatibilidade já existentes foram mantidos.

## Validação e teste no servidor

Validação isolada: `cache_database_test.lua`, `admin_self_jail_test.lua`, `jail_timeout_integration_test.lua` e `prison_client_menu_test.lua` aprovados em Lua55. Validação luac: 33 arquivos do XT Prison, 157 do Forge Core e o adaptador do PR Bridge aprovados. As seis locales JSON foram analisadas. Nenhum acesso direto a state bags encontrado nos arquivos Lua do XT Prison.

Roteiro adicional: reiniciar XT Prison e Forge Core; preencher `/jail` aguardando mais de 10 segundos antes de confirmar; conferir entrada e F9. Na gestão do Forge, conferir dados principais e executar prisão/soltura. Parar XT Prison em ambiente de teste e reabrir os menus: informações e ações devem desaparecer. Não houve restart ou escrita em banco real nesta execução.

### Teste administrativo de prisão própria

Corrigido em 01/10/2026: a seleção excluía o próprio jogador e os comandos consideravam somente emprego policial. Administradores agora podem abrir `/jail`, selecionar seu próprio nome/ID e testar a prisão; `/unjail <seu ID>` e a gestão pela lista também reconhecem administradores.

A autorização usa PR Bridge: whitelist administrativa `pr_bridge:admin`, ACE administrativa `xt-prison.admin`, `admin`, `group.admin` ou `god`, ou permissão `admin`/`god` da framework. Não foram alteradas configurações de permissão da base. Policiais sem autorização administrativa continuam sem seleção própria; jogadores comuns continuam sem acesso. A lista exige personagem carregado, proximidade de 5 metros e mesma instância. Permissão e destino são revalidados após o diálogo. Uma entrada na prisão que falha não produz notificação de sucesso.

Homologar com um administrador sozinho, um policial não-admin próximo de outro jogador e um jogador sem permissão. Não interpretar esses testes isolados como aprovação no jogo.

1. Reiniciar `xt-prison` e conferir as mensagens de criação/verificação das três tabelas, sem erros. **Não excluir tabelas reais para testar.** Instalação do zero deve ser testada em banco separado.
2. Conferir `xt_prison_settings`: deve existir a linha `global`. Abrir `/prisonconfig`, alterar uma opção, salvar e reiniciar; conferir persistência.
3. Prender alguém, alterar pena pela lista, testar minutos/horas/dias e relógios real/jogo. Confirmar redução e metadata `injail`.
4. Testar checkout e `/unjail`, devolução de itens, pena perpétua e mudança de personagem. Nenhuma informação deve vazar entre personagens.
5. Desconectar preso e reconectar; reiniciar o recurso com jogador preso. Conferir pena recuperada e ausência de erros.
6. Com dois jogadores, conferir terminais ocupados, liberação após disconnect, cooldown, alarme, portões e entrada tardia de observador.

## Limites desta etapa

Sem certificação de desempenho sob carga ou auditoria completa de segurança dos eventos legados. Há setters/ações de compatibilidade acionáveis pela rede cuja autorização de gameplay merece uma etapa própria de revisão; a migração para cache não transforma automaticamente esses eventos em contratos seguros. Servidor e cliente continuam usando os eventos públicos existentes.

Após aprovação do responsável, atualizar o status no plano do PR Bridge.
