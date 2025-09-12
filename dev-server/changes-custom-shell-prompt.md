# Starship Prompt Setup for Bash

This document explains how to install and configure the **Starship** prompt for **bash**, including custom fonts for symbols.

---

## 1. Install Starship

```bash
curl -sS https://starship.rs/install.sh | sh
```

Or via your package manager:

- Debian/Ubuntu: `sudo apt install -y starship`

Verify install:
```bash
starship --version
```

---

## 2. Install a Nerd Font (for icons/symbols)

Starship works with any font, but for full symbols/icons, install a Nerd Font.

Example (FiraCode Nerd Font):

```bash
mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts
wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/FiraCode.zip
unzip -o FiraCode.zip
fc-cache -fv
```

Then set your terminal font to **FiraCode Nerd Font**.

---

## 3. Enable Starship in Bash

Add this line to the end of `~/.bashrc`:

```bash
eval "$(starship init bash)"
```

Reload your shell:
```bash
source ~/.bashrc
```

---

## 4. Configure the Prompt

Create/edit the config file:

```bash
mkdir -p ~/.config
nano ~/.config/starship.toml
```

Example `~/.config/starship.toml`:

```toml
# Starship prompt configuration

# Add a blank line between prompts
add_newline = true

# Directory settings
[directory]
style = "blue"
truncation_length = 3
truncation_symbol = "…/"

# Git branch display
[git_branch]
symbol = "🌱 "
style = "purple"

# Command success/error symbols
[character]
success_symbol = "[➜](bold green) "
error_symbol = "[✗](bold red) "
```

Apply changes:
```bash
source ~/.bashrc
```

---

## 5. Reset / Remove

To revert to default bash:

```bash
sed -i.bak '/starship init bash/d' ~/.bashrc
rm -f ~/.config/starship.toml
source ~/.bashrc
```

To uninstall:
- Debian/Ubuntu: `sudo apt remove -y starship`

