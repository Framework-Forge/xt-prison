# Testes da migração do XT Prison para o PR Bridge

## Preparação

Use dois jogadores próximos: um policial e um alvo. Anote os IDs exibidos no servidor. Nos exemplos abaixo, `1` é o policial e `2` é o alvo; troque pelos IDs reais.

No console do servidor:

```text
restart pr_bridge
restart xt-prison
```

Confirme no console que o `xt-prison` inicia sem erro de módulo, callback, banco ou locale. O manifesto do XT Prison exige somente `pr_bridge`.

No jogo, com permissão administrativa:

```text
/setjob 1 police 0
```

O emprego também pode ser `lspd`, pois ambos estão em `configs/server.lua`.

## 1. Comandos e permissão policial

1. Com o policial, execute `/jailtime`. Deve informar que não existe pena ativa.
2. Com um civil, execute `/prisoners`. O acesso deve ser negado.
3. Com o policial, execute `/prisoners`. O menu Forge/PR Bridge deve abrir, mesmo vazio.
4. Deixe o alvo a menos de 5 metros do policial e execute `/jail`.
5. Selecione o alvo no diálogo, informe a quantidade, a unidade (minutos, horas ou dias) e o relógio (vida real ou tempo do jogo).
6. Repita com o alvo a mais de 5 metros. A sentença não deve ser aplicada.

## 2. Entrada na prisão

Após sentenciar o alvo:

1. O emprego deve mudar para `unemployed` quando `RemoveJob = true`.
2. Os itens devem ser apreendidos.
3. O jogador deve receber uniforme, teleporte para um spawn configurado, som e alerta de entrada.
4. `/jailtime` deve informar o tempo restante.
5. Em **vida real**, o vencimento deve continuar avançando mesmo com o jogador desconectado. Em **tempo do jogo**, cada minuto da pena deve usar o número de segundos configurado no painel.
6. Consulte o banco:

```sql
SELECT * FROM xt_prison WHERE identifier = '<citizenid>';
SELECT owner, data FROM xt_prison_items WHERE owner = '<citizenid>';
```

A primeira consulta deve conter o tempo atual e os detalhes da sentença na coluna `sentence`. A segunda deve conter o inventário apreendido em JSON.

## 3. Persistência e reconexão

1. Com o alvo ainda preso, desconecte e conecte novamente.
2. Ele deve voltar para a prisão com o tempo salvo.
3. Os itens apreendidos não podem reaparecer no inventário.
4. Ainda preso, execute no console `restart xt-prison`.
5. Reconecte o alvo se necessário. A pena e o registro de itens devem continuar no banco.
6. Verifique novamente as duas consultas SQL da etapa anterior.

## 4. Roster e alteração de pena

1. Com o policial, execute `/prisoners`.
2. Abra o prisioneiro e altere a pena escolhendo quantidade, unidade e relógio.
3. No alvo, `/jailtime` deve mostrar os minutos restantes equivalentes.
4. Abra novamente o roster e liberte o alvo.
5. Repita a sentença e teste o comando direto:

```text
/unjail 2
```

O comando e o roster devem produzir o mesmo resultado.

## 5. Liberação e devolução de inventário

1. Antes da prisão, dê ao alvo dois ou três itens com metadata, se o inventário permitir.
2. Durante a prisão, obtenha um item permitido em `AllowedToKeepItems`.
3. Liberte o jogador pelo roster ou `/unjail 2`.
4. Os itens originais devem voltar com quantidade e metadata.
5. O item permitido obtido na prisão deve permanecer.
6. A linha correspondente deve desaparecer de `xt_prison_items` somente após a restauração completa:

```sql
SELECT owner, data FROM xt_prison_items WHERE owner = '<citizenid>';
```

Se algum item não puder ser devolvido, a notificação deve informar a falha e a linha deve permanecer no banco para nova tentativa.

## 6. Checkout, cantina e enfermaria

1. Vá ao checkout em `1836.5, 2592.05, 46.35` e use o target nativo do PR Bridge.
2. Com pena ativa, o sistema deve informar o tempo restante.
3. Faça duas consultas em menos de cinco segundos. A segunda deve ser bloqueada pelo cooldown.
4. Vá ao NPC da cantina em `1778.31, 2560.56, 45.62`, use **Receive Meal** e confirme barra de progresso e entrega de comida/bebida.
5. Vá ao médico em `1746.37, 2467.26, 45.85`, use **Receive Check-Up** e confirme progresso e callback de cura configurado.
6. Reinicie `xt-prison` e confirme que os NPCs e targets aparecem uma única vez, sem duplicação.

## 7. Fuga da prisão

1. Dê ao prisioneiro o item `trojan_usb`.
2. Confirme que a quantidade de policiais atende `MinimumPolice`.
3. Use um terminal configurado em `HackZones`.
4. O skill check do PR Bridge deve abrir; o terminal deve impedir uso simultâneo.
5. No sucesso, confirme progresso, porta aberta, estado global do terminal e cooldown.
6. Saia do raio de 200 metros da prisão enquanto ainda estiver preso.
7. O alarme, dispatch configurado e limpeza da pena da fuga devem ser acionados.
8. Os itens apreendidos devem ser removidos conforme a regra de fuga existente; confirme no banco.
9. Após o cooldown e após `restart xt-prison`, as portas devem voltar ao estado fechado.

## 8. Critérios de aprovação

Considere a migração funcionalmente aprovada quando:

- o console e o F8 não exibirem erros do XT Prison;
- os menus, inputs, alertas, progresso, skill check e targets forem do PR Bridge;
- sentença, reconnect, restart, roster e liberação preservarem o tempo correto;
- apreensão e devolução não duplicarem nem perderem itens;
- cantina, enfermaria, checkout e fuga funcionarem;
- `xt_prison` e `xt_prison_items` refletirem cada transição;
- reiniciar o recurso não duplicar NPCs, zonas ou targets.

## 8. Painel de configuração no jogo

1. Entre com uma conta que possua `xt-prison.admin`, `group.admin`, `admin` ou acesso ao comando.
2. Execute:

```text
/prisonconfig
```

Também abra o painel administrativo do Forge Core, entre em **Configurações do servidor** e selecione **Sistema prisional**. O mesmo painel deve abrir; pressione voltar e confirme que retorna para **Configurações do servidor**, sem fechar a interface nem perder o foco.

3. Em **Regras da pena**, altere a unidade padrão, o relógio padrão e os segundos reais por minuto do jogo. Salve e abra `/jail`; os novos padrões devem aparecer selecionados.
4. Em **Locais e zonas**, teste o ponto de liberdade, checkout e roster usando a posição atual e o Draw Laser. Use o teleporte para conferir cada coordenada.
5. Desenhe o limite da prisão primeiro como SphereZone e depois como PolyZone. Saia do limite com um prisioneiro e confirme o fluxo de fuga.
6. Em **NPCs**, troque o modelo/cenário, abra o posicionador com preview e confirme com ENTER. Cantina e médico devem reaparecer uma vez, já na nova posição.
7. Adicione, edite, teleporte e remova pontos de entrada. Mantenha ao menos um ponto antes de prender alguém.
8. Adicione um terminal, configure a porta, desenhe sua SphereZone e confirme que o target aparece sem reiniciar o recurso.
9. Em **Fuga da prisão**, altere duração do hack, alarme, cooldown e policiais mínimos; confirme o novo comportamento.
10. Reinicie `xt-prison`, abra `/prisonconfig` novamente e confirme que tudo foi recuperado da tabela:

```sql
SELECT id, data, updated_at FROM xt_prison_settings;
```

11. Faça a alteração conectado com outro jogador. O segundo cliente deve receber NPCs e zonas atualizados sem relogar.

## 9. Testes dos relógios da pena

1. Configure `1` minuto em **vida real**, prenda o alvo e aguarde 60 segundos. O tempo deve zerar.
2. Configure `2` minutos em **vida real**, desconecte o alvo por mais de 60 segundos e reconecte. Deve restar no máximo 1 minuto.
3. No painel, configure `2` segundos reais por minuto do jogo.
4. Prenda o alvo por `5` minutos em **tempo do jogo**. A pena deve zerar em aproximadamente 10 segundos enquanto ele estiver preso.
5. Repita usando `1` hora e confirme que a conversão cria 60 minutos; usando `1` dia, deve criar 1440 minutos.

## 10. Critérios de aprovação

Além dos critérios anteriores, confirme que:

- todas as notificações visíveis do XT Prison usam a interface nativa do PR Bridge;
- o painel rejeita jogadores sem permissão;
- `xt_prison_settings` persiste o painel e publica mudanças em tempo real;
- minutos, horas e dias funcionam nos comandos e no roster;
- vida real considera o período offline e tempo do jogo respeita o multiplicador configurado.
