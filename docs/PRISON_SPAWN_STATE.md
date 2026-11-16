# Estado persistente da prisão e integração com space_spawn

## Recursos envolvidos

- `xt-prison`: estado por personagem, banco, metadata, confirmação de fuga e entrada.
- `space_spawn`: consulta ao estado pelo PR Bridge, bloqueio visual e nascimento obrigatório.
- `pr_bridge`: usa-se o adaptador existente `bridge/prison/server`; não foi necessário alterá-lo.

## Estados

| Estado no banco/cache | Metadata `prisonStatus` | Metadata `injail` | Seletor |
| --- | --- | --- | --- |
| `jailed` | `jailed` | Minutos da pena | Vermelho, sem destinos nem voltar; somente Entrar no mundo |
| `fugitive` | `fugitive` | 0 | Destinos normais |
| `free` | `free` | 0 | Destinos normais |

O banco `xt_prison` é a fonte persistente. Cache do PR Bridge e metadata refletem esse estado, vinculados à identidade do personagem, não apenas ao ID temporário da sessão. Na ausência de registro antigo, `injail` pode inicializar a pena legada.

Uma fuga confirmada pelo servidor preserva a condenação e os minutos restantes, mas suspende a contagem enquanto o personagem estiver foragido. Prender novamente define uma nova pena; liberar remove a pena e muda para `free`.

## Inicialização e segurança

- Ao iniciar o recurso, a coluna `status` é criada automaticamente quando estiver ausente. Penas antigas positivas viram `jailed`; as demais, `free`. Uma reinicialização não sobrescreve fugitivos existentes.
- A fuga somente é confirmada se o jogador estiver preso e fora do perímetro verificado pelo servidor. Alarmes não condicionam o registro da fuga.
- O resultado é persistido imediatamente; uma falha ao salvar restaura o estado anterior. Ações concorrentes usam reserva no cache por personagem.
- O seletor consulta o estado ao abrir, ao confirmar e novamente depois da animação normal de entrada.
- A entrada de preso exige confirmação do XT e aplica as coordenadas novamente no servidor, com bucket 0, ignorando última posição, casa e destinos normais.
- O destino autoritativo deve ser um dos pontos de entrada configurados dentro do perímetro da prisão. Sem ponto válido ou sem resposta do provedor, a entrada é bloqueada e não é liberada como nascimento comum.
- Se XT estiver parado, personagens com metadata de prisão também não recebem seleção livre. Personagens livres e foragidos continuam elegíveis para destinos normais.

## Validação local e teste em jogo

Validação local: sintaxe Lua com `luac55.exe`, testes Lua de regressão e de persistência/migração, teste do contrato do seletor e teste JavaScript do bloqueio visual. Esses testes usam ambientes simulados, sem alterar o banco em execução.

**Pendente de aprovação em FiveM:**

1. Reiniciar `xt-prison` e depois `space_spawn`; conferir a migração sem erro no console.
2. Prender um personagem, desconectar e reconectar: tela vermelha sem destinos/Voltar, com Entrar no mundo.
3. Confirmar a entrada com a última localização fora da prisão: o personagem deve aparecer dentro dela.
4. Fugir atravessando o perímetro: conferir `status = fugitive` e a pena preservada no banco.
5. Reconectar como foragido: destinos e cores normais; os minutos restantes da condenação não diminuem enquanto foragido.
6. Prender novamente e depois liberar: conferir estados `jailed` e `free`, respectivamente.
7. Alternar personagens para verificar isolamento entre suas penas.

Nenhum reinício de FXServer ou teste conectado foi feito automaticamente. A aprovação desta etapa depende desses testes em jogo.
