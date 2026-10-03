# Integração de portas — Forge

## Estado

Editor/registro implementados, validados com luac e testes isolados; aguardando
aprovação no FiveM e captura das portas que ainda não têm geometria cadastrada.
Nenhuma alteração em ox_doorlock ou PS Housing.

## Contrato

XT Prison usa `@pr_bridge/bridge/doorlock/server`. Portas existentes são reutilizadas
pelo nome de `escapes[].doors` / `HackZones[].gates`, agrupadas em `forge-prison`, sem substituir permissões,
geometria ou tipo de animação. O estado usa o export `setDoorState`.
Hack, cooldown, configuração e encerramento usam o mesmo adaptador. Alarmes usam
cache próprio por ambiente e não fecham portas globalmente ao expirar.
Trancas já pertencentes a housing/outros grupos não são apropriadas pela prisão.

Para portas inexistentes, use **Fuga da prisão → ambiente → Portas desta fuga**
para capturar porta simples/dupla. O resultado fica em `settings.doors` e é salvo
no banco/JSON conforme o modo de persistência. Os dados são os mesmos de
`createDoor` do housing/doorlock:
`coords`, `model`, `heading`, `rotation`, ou `doors` com duas folhas.
São preservados `doorType`, `closed`, `open`, `slideDirection`, `slideDistance`,
`openSpeed`, `closeSpeed`, permissões e outros parâmetros do provider.
O grupo é criado implicitamente pelo campo `doorGroup` do provider.

### Acesso policial e abertura pelo terminal (02/10/2026)

Na criação/sincronização, as portas da prisão recebem `groups = { police = 1 }`,
incluindo trancas já existentes. São removidas autorizações alternativas por
personagem/item/senha/lockpick, sem mudar geometria ou IDs. Exceções administrativas
globais do próprio doorlock continuam sendo decisão de sua configuração.

O terminal não tenta abrir como o jogador: depois das validações de autoria,
distância e estado, o adaptador usa evento **local de servidor** `ox_doorlock:setState`
e relê a porta para confirmar o estado. Não altera o ACL do evento recebido pela rede
nem grava o banco a cada troca transitória de estado. Referência de contexto local:
https://docs.fivem.net/docs/scripting-manual/working-with-events/triggering-events/

O problema foi reproduzido com a função real `setDoorState` instalada: contexto
de jogador/zero pode recusar export mesmo com a porta registrada. Agora recusa de
estado ou de validação retorna motivo e gera diagnóstico do terminal no servidor.
Teste: `tests/terminal_provider_origin_test.lua`. Aprovação no FiveM ainda pendente.

**Não usar coordenadas do terminal como coordenadas da porta.** O XT original não
inclui modelo/posição das folhas. Sem esses dados, uma porta ausente gera diagnóstico
`missing_door_geometry`, em vez de criar uma tranca inválida silenciosamente.

## Testes

Após atualizar o manifest, reiniciar a base carregando PR Bridge antes de XT Prison;
verificar grupo no doorlock, tranca inicial, hack e cooldown por ambiente.
Reiniciar novamente e confirmar que não duplicou portas. Testar porta dupla e tipo
especial com os parâmetros reais cadastrados. Testar também após reiniciar doorlock.
Validação isolada em `tests/door_provider_test.lua`; não substitui teste no jogo.
O cliente publica explicitamente `bridge/doorlock/client.lua` no PR Bridge; caso
o recurso montado ainda não tenha esse arquivo, há diagnóstico sem abortar o editor.
Veja também [Editor e ambientes](PRISONBREAK_EDITOR.md).
