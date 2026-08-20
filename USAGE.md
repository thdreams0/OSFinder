# OSFinder - Como Usar (How to Use)

## Introdução Rápida

O OSFinder é uma ferramenta TUI (Text User Interface) leve que boota de USB e permite buscar e baixar ISOs de sistemas operacionais da internet via Supabase - ideal para computadores sem sistema operacional instalado.

## Pré-requisitos

### Para Criar o USB Bootable:
- USB drive (mínimo 128MB, recomendado 2GB+)
- Computador com Windows, Linux ou macOS para criar o USB
- Syslinux instalado no MBR do USB

### Para Rodar em Computadores Sem OS:
- Qualquer computador com BIOS ou UEFI
- Conexão com internet (necessária para baixar ISOs)
- Suporte bootável de USB no firmware do computador

## Passo a Passo: Criar o USB Bootable

### Opção 1: Usando o script automatizado

```bash
# Do diretório do projeto
chmod +x setup/usb_setup.sh
./setup/usb_setup.sh /dev/sdX
```

Substitua `/dev/sdX` pelo seu dispositivo USB (ex: `/dev/sdb`, `/dev/sdc`).

**Atenção**: Isso apagará todos os dados no USB.

### Opção 2: Manual (se o script falhar)

1. Formate o USB em FAT32
2. Instale sysloader no MBR:
   ```bash
   dd bs=440 count=1 conv=notrunc if=/usr/lib/syslinux/mbr/mbr.bin of=/dev/sdX
   ```
3. Copie os arquivos do OSFinder para o USB:
   - `osfinder.sh`
   - `.env` (com credenciais Supabase)
   - `syslinux.cfg`
   - `boot/grub/grub.cfg`
4. Reinicie o computador e bootie do USB

## Como Usar o OSFinder

### 1. Boot do Computador

Insira o USB e reinicie o computador. Entre no firmware (BIOS/UEFI) geralmente com:
- **F8**, **F12**, **Del** ou **F2** para menu de boot
- Selecione o dispositivo USB

### 2. TUI Interface

Ao bootar, aparecerá um menu ASCII do OSFinder:

```
  ▄▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀

OSFinder TUI - Bare Metal ISO Downloader

Search and download operating system ISOs

Press Enter to search, numbers to select
```

### 3. Search de OS

Você tem duas opções:

**Opção A - Digitar nome:**
```
Search OS> ubuntu
```

**Opção B - Usar códigos numéricos:**
```
1. Ubuntu 22.04 LTS
2. Debian 12 AMD64
3. Fedora 38 AMD64
4. Kali Linux Rolling
```

Digite o número correspondente e pressione Enter.

### 4. Baixar ISO

O script vai:
1. Consultar o Supabase pela busca
2. Mostrar resultados disponíveis
3. Baixar o ISO selecionado via `curl -L`

Durante o download, aparecerá uma progress bar ASCII:

```
▌▌▌▌▌▌▌▌▌▌░░░░░ 45%
```

### 5. Pós-Download

Após o download concluir:
- ISO salva em `/tmp/ nome-do-sistema.iso`
- Mensagem de sucesso aparece
- Pressione Enter para retornar ao menu
- Pode fazer nova busca ou desligar o computador

## Exemplos Práticos

### Exemplo 1: Baixar Ubuntu 22.04

1. Boot do USB → OSFinder TUI aparece
2. Digite `1` ou `ubuntu` e aperte Enter
3. Veja "Ubuntu 22.04 LTS" nos resultados
4. Confirme a seleção (número correspondente)
5. Assistir progress bar do download
6. Quando terminar: ISO em `/tmp/ubuntu-22.04.1-desktop-amd64.iso`
7. Use esse ISO para criar mídia de instalação ou bootar via QEMU

### Exemplo 2: Baixar Debian 12

1. Boot do USB → OSFinder TUI aparece
2. Digite `2` ou `debian` e aperte Enter
3. Selecione no results list
4. Download via curl começa automaticamente
5. ISO salva em `/tmp/debian-12.5.0-amd64-netinst.iso`

## Configuração

### Editar Credenciais Supabase

Edite `config/.env`:

```bash
SUPABASE_URL="https://SEU_PROJETO.supabase.co/rest/v1/list"
SUPABASE_ANON_KEY="sb_secret_SUA_CHAVE_ANAN"
```

### Adicionar Novos ISOs na Base de Dados

1. Acesse seu projeto Supabase
2. Vá ao SQL Editor
3. Insira nova linha na tabela `list`:
   ```sql
   INSERT INTO list (os_name, link_to_download) VALUES (5, 5);
   -- Code 5 = novo ISO mapeado em osfinder.sh
   ```
4. Atualize a função `OS_MAPPING()` em `src/osfinder.sh` para code 5

## Solução de Problemas

### "Nenhum resultado encontrado"

- Verifique se digitou corretamente (case-insensitive no Supabase)
- Certifique-se de que o ISO está na tabela `list`
- Tente códigos numéricos: `1`, `2`, `3`, `4`

### Download falha

- Verifique conexão com internet
- Confira se o URL da tabela `link_to_download` está correto
- O ISO pode ser muito grande para a conexão

### USB não boota

- Verifique se sysinstall foi instalado corretamente no MBR
- Confirme se o USB está em FAT32
- Tente reinstalar com o script `setup/usb_setup.sh`

### TUI não aparece direito

- O terminal precisa suportar `tput` e `ncurses`
- Variáveis de ambiente: `export TERM=dumb`
- Em alguns firmware antigos, pode precisar de `setterm`

## Notas Importantes

- ✅ **Não salva ISOs no USB**: O download vai para `/tmp/` do computador alvo
- ✅ **Conexão obrigatória**: Internet necessária para cada uso
- ✅ **Compatible**: BIOS legacy e UEFI
- ✅ **Tamanho pequeno**: < 5MB no USB total
- ⚠️ **ISO size varia**: De 500MB a 5GB+ - certifique-se de espaço em disco

## Comandos Rápidos

| Ação | Tecla/Comando |
|------|--------------|
| Search OS name | Digite e Enter |
| Selecionar ISO 1 | Pressione `1` e Enter |
| Selecionar ISO 2 | Pressione `2` e Enter |
| Selecionar ISO 3 | Pressione `3` e Enter |
| Selecionar ISO 4 | Pressione `4` e Enter |
| Nova search | Enter vazio no prompt |
| Sair do programa | Reiniciar ou desligar |

---

**OSFinder** - Download ISOs bare-metal friendly via Supabase TUI.