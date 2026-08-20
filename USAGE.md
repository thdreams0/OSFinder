# OSFinder - Como Usar (How to Use)

## O que é

O OSFinder é uma TUI (Text User Interface) que arranca a partir de uma pen USB,
boota um Alpine Linux mínimo para a RAM e permite procurar, descarregar e montar
ISOs de sistemas operativos. Ideal para computadores sem SO instalado.

## Criar a pen USB

### Do zero

```bash
# Do diretório do projeto (requer sudo)
sudo bash setup/usb_setup.sh /dev/sdX
```

Substitui `/dev/sdX` pela pen (ex.: `/dev/sdb`).
**Atenção**: todos os dados no dispositivo são apagados.

### Atualizar uma pen que já existe

Depois de alterares o `src/osfinder.sh` ou o `config/.env`, reconstrói o overlay
sem ter de recriar a pen do zero:

```bash
sudo bash setup/fix_pen.sh /dev/sdX
```

### Verificar o projeto

```bash
sudo bash installer.sh
```

Verifica a sintaxe da TUI, a presença dos ficheiros do projeto, a ligação ao
Supabase e a documentação.

## Arranque no computador alvo

1. Insere a pen e arranca a partir dela (tecla de boot: **F8**, **F12**, **Del** ou **F2**).
2. No menu GRUB, escolhe a entrada do OSFinder.
3. O Alpine arranca para a RAM e a TUI abre automaticamente no ecrã.

## A TUI

### Menu principal

```
========================================
OSFinder - Download and install an OS
========================================
Internet: Connected / OFF

  1. Search and download an OS
  2. Set up WiFi
  3. Shell (for advanced users)
  4. Power off
```

O estado da internet aparece no topo (verde = ligado, vermelho = desligado).

### Rede automática

- **Sem internet ao arrancar**: a TUI tenta ethernet (DHCP) e, se não resultar,
  abre o assistente WiFi para ligares manualmente. Se recusares, podes ligar mais
  tarde com a opção **2. Set up WiFi**.

### Assistente WiFi

1. A TUI escaneia as redes disponíveis.
2. Escolhe uma rede pelo **número** (ou escreve o nome).
3. Digita a palavra-passe (fica oculta).
4. Se a senha estiver errada, podes tentar novamente.
5. A configuração é **guardada na pen** (`etc/wpa_supplicant.conf`) e a TUI
   reconecta automaticamente nos próximos arranques, se não houver ethernet.

### Procurar e descarregar um OS

Escolhe a opção **1** no menu. Depois:

```
What do you want to install?
Type part of the name (e.g. ubuntu, debian, cachyos)
Press Enter with nothing typed to go back.

Search> ubuntu
```

- A busca é **parcial** (por nome): `ubuntu` encontra qualquer entrada que contenha "ubuntu".
- **Enter com o campo vazio** volta ao menu.
- Com resultados, aparece uma lista numerada:

```
Available results:
---------------------
  1. Ubuntu-22.04
---------------------
Type the number to download
Select> 1
```

- O download mostra uma **barra de progresso** e guarda o ISO em `/tmp/<nome>.iso` (RAM).

### Pós-download

```
Download complete: /tmp/ubuntu-22.04.iso

What next?
  1. Mount the ISO and open the installer
  2. Copy the ISO to the USB pen
  3. Search another OS
```

- **1 — Mount the ISO**: monta o ISO em `/mnt/iso` e abre um shell. Procura o
  instalador lá dentro (ex.: `./install*`, `casper`, `ubiquity`, `calamares`) e
  corre-o. Escreve `exit` para voltar à TUI.
- **2 — Copy ISO to the pen**: grava o ISO na pen (a pen é detetada pelo marcador
  `.boot_repository`) para arrancar noutra máquina.
- **3 — Search another OS**: volta à busca.

### Shell (avançado)

A opção **3** abre um shell no Alpine live (utilidade para diagnosticar rede,
partições, etc.). Escreve `exit` para voltar à TUI.

### Desligar

A opção **4** desliga o computador.

## Adicionar OS à biblioteca

Os ISOs são guardados no Supabase, na tabela `list`:

| Coluna            | Exemplo                                    |
|-------------------|--------------------------------------------|
| `os_name`         | `Ubuntu-22.04`                             |
| `link_to_download`| `https://releases.ubuntu.com/.../ubuntu.iso` |

```sql
INSERT INTO list (os_name, link_to_download) VALUES ('Debian-12', 'https://.../debian.iso');
```

Não há códigos nem mapeamento: a busca parcial e o download usam estas colunas diretamente.

## Configuração

### Credenciais Supabase

Edita `config/.env` (fora do git):

```bash
SUPABASE_URL="https://SEU_PROJETO.supabase.co/rest/v1/list"
SUPABASE_ANON_KEY="a_tua_anon_key"
```

Ao criar/atualizar a pen, as credenciais são injetadas no overlay como
`/etc/osfinder.env`, usadas pela TUI em runtime.

## Solução de problemas

### "Could not mount the ISO"
A TUI tenta carregar o módulo `loop` e criar os devices `/dev/loop*`. Se mesmo assim
falhar, usa a opção **2. Copy the ISO to the USB pen** e arranca a partir da pen.

### Sem resultados na busca
- Confirma que o nome corresponde a uma entrada da tabela `list` (busca parcial).
- Verifica a ligação (o estado `Internet` no topo).
- Confirma que `config/.env` tem as credenciais corretas.

### Download falha
- Verifica a internet (WiFi/ethernet).
- Confirma que `link_to_download` da entrada aponta para um URL válido.

### SATA / disco não detetado no boot
Corre `sudo bash setup/fix_pen.sh /dev/sdX` — o script injeta `sd_mod`/`scsi_mod`
no initramfs para discos SATA.

### Texto pequeno ou grande
A TUI deteta a resolução do monitor e escolhe uma fonte de consola maior
(por exemplo `sun12x22` em ecrãs 1080p, `solar24x32` em 1440p+).

## Notas importantes

- ✅ **Não grava ISOs na pen automaticamente**: o download vai para `/tmp` (RAM).
- ✅ **Sem internet no 1º boot**: as ferramentas necessárias vêm embutidas no overlay.
- ✅ **WiFi funciona sem ethernet**: assistente integrado + reconexão automática.
- ✅ **BIOS legacy e UEFI** suportados (GRUB).
- ⚠️ **RAM**: ISOs grandes precisam de RAM livre em `/tmp` (tmpfs). Com ISOs de
  vários GB, recomenda-se 8–16 GB de RAM no computador alvo.
- ⚠️ **Credenciais**: nunca versionadas; vivem apenas em `config/.env`.

---

**OSFinder** - Descarrega ISOs bare-metal friendly via Supabase.