# Tmux - Guía de Instalación y Configuración

## ¿Qué es Tmux?

Tmux (Terminal Multiplexer) es una herramienta que permite:
- Mantener sesiones activas en el servidor incluso si te desconectas
- Dividir la terminal en múltiples paneles
- Tener múltiples ventanas en una sola sesión SSH

## Instalación

### Ubuntu/Debian
```bash
sudo apt update
sudo apt install tmux -y
```

### CentOS/RHEL
```bash
sudo yum install tmux -y
```

### Verificar instalación
```bash
tmux -V
```

## Configuración Automática en SSH

### Opción 1: Iniciar tmux automáticamente (Recomendado)

Edita el archivo `~/.bashrc`:

```bash
nano ~/.bashrc
```

Agrega al final del archivo:

```bash
# Iniciar tmux automáticamente en sesiones SSH interactivas
# Esto NO afecta SFTP, SCP ni otras conexiones no-interactivas
if [[ $- == *i* ]] && [[ -z "$TMUX" ]] && [[ -n "$SSH_TTY" ]]; then
    tmux attach -t instalacion || tmux new -s instalacion
fi
```

Recarga la configuración:
```bash
source ~/.bashrc
```

### Opción 2: ForceCommand en SSH (NO recomendado para SFTP)

⚠️ **ADVERTENCIA**: Esta opción rompe SFTP si no se configura correctamente.

Edita `/etc/ssh/sshd_config`:

```bash
sudo nano /etc/ssh/sshd_config
```

Agrega (solo si necesitas forzar tmux para todos los usuarios):

```bash
# Permite que SFTP funcione mientras fuerza tmux en SSH interactivo
Match User root
    ForceCommand if [ "$SSH_ORIGINAL_COMMAND" = "" ]; then tmux attach -t instalacion || tmux new -s instalacion; else $SSH_ORIGINAL_COMMAND; fi
```

Reinicia SSH:
```bash
sudo systemctl restart sshd
```

## Comandos Básicos de Tmux

### Atajos de teclado (Prefix: `Ctrl+b`)

| Comando | Descripción |
|---------|-------------|
| `Ctrl+b` `d` | Desconectar de la sesión (detach) |
| `Ctrl+b` `c` | Crear nueva ventana |
| `Ctrl+b` `n` | Siguiente ventana |
| `Ctrl+b` `p` | Ventana anterior |
| `Ctrl+b` `%` | Dividir panel verticalmente |
| `Ctrl+b` `"` | Dividir panel horizontalmente |
| `Ctrl+b` `→` | Moverse al panel derecho |
| `Ctrl+b` `←` | Moverse al panel izquierdo |
| `Ctrl+b` `x` | Cerrar panel actual |
| `Ctrl+b` `[` | Modo scroll (usa flechas, `q` para salir) |

### Comandos desde la terminal

```bash
# Listar sesiones
tmux ls

# Crear nueva sesión con nombre
tmux new -s nombre-sesion

# Adjuntar a sesión existente
tmux attach -t nombre-sesion

# Matar sesión específica
tmux kill-session -t nombre-sesion

# Matar todas las sesiones
tmux kill-server

# Renombrar sesión actual
tmux rename-session -t old-name new-name
```

## Configuración Personalizada (Opcional)

Crea un archivo de configuración `~/.tmux.conf`:

```bash
nano ~/.tmux.conf
```

Ejemplo de configuración:

```bash
# Cambiar prefix de Ctrl+b a Ctrl+a (opcional)
# set -g prefix C-a
# unbind C-b
# bind C-a send-prefix

# Habilitar mouse
set -g mouse on

# Aumentar historial de scroll
set -g history-limit 10000

# Iniciar numeración de ventanas en 1
set -g base-index 1
setw -g pane-base-index 1

# Recargar configuración con Ctrl+b r
bind r source-file ~/.tmux.conf \; display "Configuración recargada!"

# Dividir paneles con | y -
bind | split-window -h
bind - split-window -v

# Mejorar colores
set -g default-terminal "screen-256color"

# Barra de estado
set -g status-bg colour235
set -g status-fg colour136
set -g status-left '#[fg=green]#S #[default]'
set -g status-right '#[fg=yellow]#(whoami)@#H #[fg=cyan]%H:%M'
```

Recarga la configuración:
```bash
tmux source-file ~/.tmux.conf
```

## Solución de Problemas

### SFTP no funciona (Connection closed by lower level protocol)

Si usas `ForceCommand` en SSH y SFTP falla:

1. Edita `/etc/ssh/sshd_config`
2. Busca la línea `ForceCommand tmux...`
3. Coméntala: `#ForceCommand tmux...`
4. Usa la Opción 1 de configuración (en `.bashrc`)
5. Reinicia SSH: `sudo systemctl restart sshd`

### No puedo salir de tmux sin desconectarme

Usa `Ctrl+b` `d` para desconectarte de la sesión sin cerrarla.
La sesión seguirá corriendo y podrás reconectarte con `tmux attach`.

### Sesión no se reconecta automáticamente

Asegúrate de que:
- El código esté en `~/.bashrc` (no en `.bash_profile`)
- El archivo tenga permisos de lectura: `chmod +r ~/.bashrc`
- Hayas recargado: `source ~/.bashrc`

## Referencias

- [Tmux Cheat Sheet](https://tmuxcheatsheet.com/)
- [Documentación Oficial](https://github.com/tmux/tmux/wiki)
- [Tmux Book](https://leanpub.com/the-tao-of-tmux/read)

---

**Autor**: Configuración para mantenimiento de servidores VPS  
**Fecha**: Enero 2026
