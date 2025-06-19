# rrepl
This plugin turns micro into an extremely simple and lightweight R ID. It integrates an interactive terminal with tmux for the REPL workflow most R users are used to.


## Usage

- `> rrepl` as a micro-command starts the R session



- `Ctrl + R` sends the current line of the cursor or the selected lines to the R session

- `Ctrl + P` inserts a baseR pipe 



- `> rrepl-stop` kills R and cleans up
- Closing the terminal with `ctrl + q` stops the tmux process automatically


## Installation

**Linux:**

```
wget https://github.com/thhaase/micro-rrepl/archive/main.zip -O rrepl.zip
unzip rrepl.zip
mkdir -p ~/.config/micro/plug/rrepl
mv micro-rrepl-main/* ~/.config/micro/plug/rrepl/
rmdir micro-rrepl-main
rm rrepl.zip
```

## tmux styling

For the plugin to work you need tmux:

```
sudo apt update
sudo apt install tmux
```

I found the default tmux a bit bland. Tmux look and usage can be customized with a `.tmux.conf` file. 

First download the catpuccin theme: 
```
mkdir -p ~/.config/tmux/plugins/catppuccin
git clone -b v2.1.3 https://github.com/catppuccin/tmux.git ~/.config/tmux/plugins/catppuccin/tmux
```
(more info [in the according repository](https://github.com/catppuccin/tmux/blob/main/docs/tutorials/01-getting-started.md))


After that copy the following code to create my `.tmux.conf` file.
```
# Create .tmux.conf with all the configuration in one command
cat > ~/.tmux.conf << 'EOF'
# ---- CATPUCCIN SETUP ----
set -g @catppuccin_flavor 'mocha'
run ~/.config/tmux/plugins/catppuccin/tmux/catppuccin.tmux
# Make the status line more pleasant.
set -g status-left ""
set -g status-right '#[fg=#{@thm_crust},bg=#{@thm_teal}] session: #S '
# Ensure that everything on the right side of the status line
# is included.
set -g status-right-length 100
# ---- ----
EOF
```
