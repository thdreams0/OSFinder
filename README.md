# OSFinder

Uma ferramenta TUI (Text User Interface) leve que boota de USB e permite procurar,
descarregar e montar ISOs de sistemas operativos em qualquer computador — incluindo
máquinas sem SO instalado (bare metal). A biblioteca de ISOs é gerida no Supabase.

## Como funciona

1. **Boot**: inseres a pen USB num computador e arrancas a partir dela.
2. **Alpine em RAM**: um Alpine Linux mínimo arranca para a RAM (diskless) e abre a TUI automaticamente.
3. **Rede**: se não houver internet, a TUI faz o setup sozinha — tenta ethernet (DHCP) e, se não houver, abre o assistente WiFi para ligares a uma rede.
4. **Busca**: escreves parte do nome do OS (ex.: `ubuntu`, `cachyos`) e a TUI consulta o Supabase (correspondência parcial).
5. **Download**: escolhes o resultado, o ISO é descarregado para `/tmp` (RAM) com barra de progresso.
6. **Pós-download**: podes montar o ISO e abrir o instalador, copiá-lo para a pen, ou procurar outro OS.

Sem necessidade de internet no primeiro arranque: o `curl`, `jq`, `wpa_supplicant`, `iw` e
as fontes de consola vêm embutidos no overlay — funciona em máquinas só-WiFi, sem ethernet.

## Estrutura

```
OSFinder/
├── src/osfinder.sh           # A TUI (menu, busca, download, WiFi)
├── installer.sh              # Script de verificação/instalação (requer sudo)
├── setup/
│   ├── usb_setup.sh          # Cria a pen bootável do zero (apaga tudo!)
│   ├── fix_pen.sh            # Atualiza uma pen existente (reconstrói o overlay)
│   └── build_apkovl.sh       # Constrói só o overlay Alpine (apkovl)
├── config/.env               # Credenciais Supabase (NÃO versionado)
└── .website/index.html       # Página web opcional
```

## Criar a pen USB

```bash
# Do zero (apaga todos os dados da pen!)
sudo bash setup/usb_setup.sh /dev/sdX

# Atualizar uma pen que já existe (após alterar osfinder.sh/config)
sudo bash setup/fix_pen.sh /dev/sdX
```

Substitui `/dev/sdX` pela pen (ex.: `/dev/sdb`). **Atenção**: todo o conteúdo do
dispositivo indicado é apagado.

Verificação do projeto (componentes, sintaxe, ligação ao Supabase):

```bash
sudo bash installer.sh
```

## Usar a TUI

No menu principal:

```
  1. Search and download an OS
  2. Set up WiFi
  3. Shell (for advanced users)
  4. Power off
```

- **Sem internet ao arrancar**: a TUI tenta ethernet e depois abre o assistente WiFi sozinha.
- **Busca**: digita parte do nome e Enter. Enter com o campo vazio volta atrás.
  O resultado é escolhido pelo número.
- **Download**: barra de progresso; o ISO fica em `/tmp/<nome>.iso` (memória RAM).
- **Pós-download**:
  1. *Mount the ISO* — monta em `/mnt/iso` e abre um shell para correres o instalador;
  2. *Copy ISO to the pen* — grava o ISO na pen (marcada com `.boot_repository`);
  3. *Search another OS* — nova busca.
- **WiFi**: o assistente escaneia, lista as redes por número, pede a palavra-passe
  (oculta) e guarda a configuração na pen (`etc/wpa_supplicant.conf`) para reconexão
  automática no próximo arranque.

## Configuração

Edita `config/.env` (mantido fora do git):

```bash
SUPABASE_URL="https://SEU_PROJETO.supabase.co/rest/v1/list"
SUPABASE_ANON_KEY="a_tua_anon_key"
```

Ao construir a pen, estas credenciais são injetadas no overlay como `/etc/osfinder.env`.

## Adicionar OS à biblioteca

Insere uma linha na tabela `list` do Supabase (colunas `os_name` e `link_to_download`):

```sql
INSERT INTO list (os_name, link_to_download) VALUES ('Ubuntu-24.04', 'https://.../ubuntu.iso');
```

A busca parcial e o download usam estas colunas diretamente — sem códigos nem mapeamento.

## Requisitos

### Para criar a pen
- Linux com `sudo` (o setup usa `parted`/`sgdisk`-compatível, `grub-install`, `unsquashfs`, `curl`)
- Pen USB com pelo menos 2 GB (a instalação Alpine + overlay ocupa < 400 MB)
- Internet na máquina de build (para descarregar o Alpine netboot e as ferramentas)

### Para arrancar (computador alvo)
- Firmware BIOS ou UEFI com boot USB
- RAM suficiente: o ISO é descarregado para `/tmp` (RAM). Com um ISO de 4 GB, precisas de
  RAM livre equivalente (8 GB é confortável, 16 GB recomendado)
- Internet para descarregar ISOs (WiFi ou ethernet)

## Solução de problemas

- **"Could not mount the ISO"**: a sessão live tenta carregar o módulo `loop` e criar
  `/dev/loop*` automaticamente; se falhar, usa a opção *Copy ISO to the pen* e arranca a partir da pen.
- **Sem internet e sem WiFi listado**: confirma que o firmware está com a interface sem fios
  ativa; pode ser preciso ativar a placa no firmware.
- **Boot preso no kernel / SATA não detetado**: corre `sudo bash setup/fix_pen.sh /dev/sdX`
  (injeta `sd_mod`/`scsi_mod` no initramfs).
- **Cores/estilo**: a TUI usa apenas verde (sucesso) e vermelho (erro); o resto é texto simples.
- **Texto pequeno/grande**: a TUI escolhe automaticamente uma fonte de consola maior
  conforme a resolução do monitor (via `setfont`).

## Notas

- O download vai para **RAM** (`/tmp`), nunca para a pen — nada fica persistido no PC alvo.
- Não são necessários códigos numéricos: a busca é por nome (correspondência parcial).
- As credenciais Supabase nunca são versionadas — vivem apenas em `config/.env`.
