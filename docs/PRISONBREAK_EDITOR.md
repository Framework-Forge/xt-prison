# Editor de fuga e configurações do cliente

Status: implementação validada em Lua/testes isolados; aguardando aprovação no FiveM.

## Índice

- [Acesso](#acesso)
- [Persistência JSON](#persistência-json)
- [Ambientes de fuga](#ambientes-de-fuga)
- [Terminais](#terminais)
- [Cliente](#cliente)
- [Validação no servidor](#validação-no-servidor)

## Acesso

Administrador: `/prisonconfig`, usando RegisterContext, diálogos e ferramentas
de posicionamento do PR Bridge. Implementações dos minigames Glitch preservadas;
a opção de notificações externas foi desativada na configuração da base Forge.

## Persistência JSON

`data/settings.json` contém as configurações completas: `locations.hacks`,
`escapes`, `doors`, `entryAlert` e os locais do cliente. Cada salvamento cria
`data/settings.backup.json`. No modo padrão database, o banco continua a origem
de leitura e o JSON é uma cópia verificada, atualizada também na inicialização.
Para usar exclusivamente o JSON como origem, definir antes do start:
`set xt-prison:settingsStorage file`. Não editar a cópia JSON esperando que ela
sobrescreva o banco no modo database.

## Ambientes de fuga

**Fuga da prisão → Criar ambiente de fuga → Fuga A/B/...**.
Cada ambiente tem ID estável, nome, lista de portas e pontos de alarme próprios.
Os cadastros antigos migram para **Fuga original**, sem apagar terminais/portas.

1. Em **Portas desta fuga**, capture porta simples/dupla fechada com Draw Laser,
   ou selecione uma tranca já registrada (somente grupo de prisão ou sem grupo).
2. Adicione os terminais; em **Editar dados**, selecione uma ou várias portas
   do mesmo ambiente e o minigame/item/dificuldade.
3. Para Fleeca/Plasma, use **Animação do hack + gizmo** e confirme a posição e
   direção do ped animado segurando a ferramenta. Não precisa digitar coordenadas.
4. Em **Pontos de alarme e teste**, cadastre os pontos deste ambiente.
5. Em **Regras do alarme desta fuga**, ajuste duração e probabilidades. Falha
   padrão: 100%; sucesso padrão: regra anterior, ou 100% se ausente.

Um terminal libera somente suas portas selecionadas. Falha só ativa os alarmes
do seu ambiente. Não é permitido compartilhar uma porta entre dois ambientes.
Dentro do mesmo ambiente, vários terminais podem liberar uma porta; ela só volta
a fechar quando nenhum desses terminais estiver em cooldown ativo.
Erro ao abrir uma das portas reverte as demais abertas pela tentativa.
Salvamento/reinicialização invalida timers antigos e reinicia estados transitórios.
Excluir uma fuga remove seus terminais/alarmes, mas não apaga trancas persistidas.

Schema: `escapes[].{id,name,doors,alarms,alarmLength,alarmFailChance,alarmSuccessChance}`;
`locations.hacks[].{escapeId,gates,game,animation,...}`. `gate` permanece como
primeira porta para compatibilidade. Alarmes antigos em `prisonBreak.alarms`
são apenas referência legada; o editor atual usa `escapes[].alarms`.

O adaptador replica o contrato observado em `ps-housing/server/doors.lua`:
modelo/posição/heading/rotação, duas folhas quando necessário, grupo persistente,
estado inicial fechado e distância de carregamento. Usa `createDoor`, preserva
IDs existentes e publica registro nativo no cliente pelo PR Bridge. Não altera
o housing ou o ox_doorlock. Trancas de outros grupos não são tomadas pela prisão.

### Arquivo do adaptador não encontrado

O arquivo `pr_bridge/bridge/doorlock/client.lua` existe no checkout e agora consta
explicitamente em `files` no manifest do PR Bridge. O erro observado significa
que o cliente não conseguiu lê-lo no recurso montado; o estado real de deploy/
montagem precisa ser confirmado no servidor. Atualize ambos os recursos e reinicie
**pr_bridge antes de xt-prison** (preferencialmente reinicialização completa da base,
pois outros recursos dependem do bridge). Não executamos restart nesta alteração.
O editor não morre mais ao carregar se o arquivo faltar: informa o problema e
tenta carregar novamente ao sincronizar portas. Isso não substitui o remount.

## Terminais

Menu principal: **Fuga da prisão → ambiente → Locais de fuga e hacks Glitch**.
Cada terminal expõe escolha de hack/item, captura de porta simples/dupla,
PolyZone e **Animação do hack + gizmo**. O primeiro posicionamento usa
`placeAnimatedPed`; em seguida o gizmo ajusta um ped animado com a ferramenta.
Confirmar/cancelar remove as entidades de prévia. As portas capturadas ficam
em `settings.doors`, são persistidas e registradas no grupo `forge-prison`.
Sem a captura real, o antigo terminal sozinho ainda não contém a geometria
necessária para criar a porta. A tela **Verificar trancas registradas** mostra IDs.

Adicionar/excluir terminais, associar nome da porta, configurar item/quantidade,
raio ou desenhar PolyZone e escolher minigame por terminal.
Opções: Circuit Breaker, Data Crack, Brute Force, Plasma Drilling e Fleeca Drilling.
Configurar dificuldade, nível do Circuit Breaker e vidas do Brute Force.
Não usa `pr_lib.skillCheck`; chama `pr_lib.minigame.Start` com o provider Glitch.
Referência: https://minigames.glitchstudios.dev/

Plasma/Fleeca exigem posição e direção do ped, capturadas com posicionador ou
posição atual. Até 10m do terminal. A geometria da porta é independente do ped.
Sem posicionamento, a perfuração é bloqueada. O Glitch gerencia suas animações.

Ao encerrar o hack (sucesso, falha, erro, logout ou parada), o serviço de emotes
do PR Bridge cancela o emote/cache de props e remove apenas os novos objetos de
tablet/drill pertencentes à sessão e anexados ao ped. Não remove objetos de outros
players nem props preexistentes. `ClearPedTasks` sozinho não limpava o tablet.
Validação: `tests/hack_prop_cleanup_test.lua`, com fluxo real de execução do hack.

### Inicialização de targets e perfurações (02/10/2026)

- Targets só são criados após aplicar as configurações persistidas. O carregamento
  inicial aguarda o callback por até 20 segundos e tenta novamente se necessário.
- Hook do cliente: `onClientResourceStart`; lifecycle de jogador vem do PR Bridge.
  Aplicação de configurações recria targets em handler separado do checkout.
- Criação parcial é revertida, com nova tentativa; logout remove targets, login
  e reinício do bridge recriam sem duplicar registros. Item/policiais/cooldown
  continuam sendo requisitos de interação e as verificações do servidor permanecem.
- XT usa explicitamente `bridge/minigames/glitch/client.lua`, mesmo se o adapter
  genérico tiver sido selecionado antes do Glitch estar pronto. Não usa fallback
  skill check para os cinco minigames desta funcionalidade.
- Assinaturas conferidas no recurso instalado: Fleeca `StartDrilling()` sem
  parâmetros; Plasma `StartPlasmaDrilling(difficulty)` com dificuldade entre 1–10.
- Ped assume coordenada/direção cadastradas e inicia idle de perfuração. Fleeca
  chama diretamente `StartDrilling()` pelo bridge, sem inicialização duplicada.
  Plasma mantém pré-carregamento de animação, modelo e scaleform `VAULT_LASER`.
  Glitch continua responsável pelo próprio minigame, prop/câmera e animações internas.
- Na base Forge, `glitch-minigames/shared/config.lua` usa
  `usingGlitchNotifications = false`: o export `glitch-notifications:ShowNotification`
  não está disponível. XT mantém avisos pelo PR Bridge. Após alterar essa opção,
  reinicie também o Glitch para limpar uma tentativa interrompida por exceção.
- Erro de carregamento/execução não é convertido em falha normal para disparar
  alarme/consumir item; gera diagnóstico no F8 e limpa a sessão. Rejeições anteriores
  ao início informam item ausente, cooldown, terminal não sincronizado etc.

### Sequência e limpeza de tentativas

Ao confirmar o destrancamento, o servidor limpa `isBusy` e `lastHacker` daquele
terminal, mantendo apenas o estado de hack/cooldown e os vínculos com suas portas.
Cancelamento, recusa, logout ou desconexão liberam a reserva do jogador; a limpeza
não depende de ele ainda estar na zona e não pode liberar a reserva de outro player.
O cliente mantém o ped parado até concluir o progresso e receber a confirmação das
portas, evitando aprovação do minigame seguida de recusa por distância.

O cooldown é independente por terminal. O mesmo target usado com sucesso fica
inativo durante esse prazo; outros terminais continuam disponíveis conforme seus
requisitos. Portas compartilhadas só são retrancadas após o último cooldown ativo.
Caso o item exigido seja consumido, a opção pode permanecer oculta até repô-lo.

Teste: `tests/terminal_sequence_test.lua` integra os módulos reais de cliente e
servidor com dependências simuladas, cobrindo Fleeca A → Data Crack B, recusa e
nova tentativa, compartilhamento de portas, cooldown e limpeza. Ajustes de sequência
validados com `luac` e 15 suítes; aguardam aprovação desta sequência no FiveM.

Teste isolado: `tests/drill_target_startup_test.lua` usa a configuração e adapter
reais com exports/natives simulados, incluindo assinaturas, refresh/retry de targets
e execução animada de ambos os drills. Não substitui aprovação dentro do FiveM.

## Cliente

NPCs agora usa listas `npcs.canteen` e `npcs.doctor`, migrando os pontos antigos.
Pode adicionar, editar, posicionar e excluir até 30 NPCs de cada tipo.
Alarmes usa `escapes[].alarms`, migrando os pontos antigos; até 20 por ambiente.
**Pontos de alarme e teste** inclui acionar/parar sem depender de probabilidade.
Chance de falha de cada ambiente pode ser ajustada; o padrão atual é 100%.
Nomes nativos de alarme são globais no GTA: repetir o mesmo nome em vários pontos
ativa props em vários interiores, mas não cria emissores espaciais independentes.
Falha ao preparar um identificador gera diagnóstico no console.

Locais e zonas: liberdade, checkout de pena (posição/dimensões/rotação), roster,
limite da prisão e pontos de entrada com emote. NPCs: cantina e médico com modelo,
cenário, duração e posicionamento. Aviso de entrada: ativação, título e mensagem.
Alarme: posição do interior, identificador do interior, prop e nome nativo GTA.
Mudar a coordenada não transforma um alarme GTA em som espacial arbitrário.

## Validação no servidor

Confere item/quantidade, policiais mínimos, distância/PolyZone e autoria do hack.
JSON não armazena funções Lua. Ao salvar, configurações são publicadas e zonas
recriadas. Aprovação funcional ainda depende de testes no FiveM.

Suítes: `escape_environments_test.lua` (migração, ownership, alarmes isolados,
rollback de abertura e cooldown compartilhado), `editor_flow_test.lua` (fluxo real dos menus) e
`gizmo_npc_alarm_test.lua` (scripts reais de gizmo/NPCs/alarmes com natives simulados).
