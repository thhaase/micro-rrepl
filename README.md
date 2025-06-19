# rrepl
This plugin turns micro into an extremely simple and lightweight R ID. It integrates an interactive terminal with tmux for the REPL workflow most R users are used to.


## Usage

- `:rrepl` starts persistent R session



- `Ctrl + R` sends the current line of the cursor or the selected lines to the R session

- `Ctrl + P` inserts a baseR pipe 



- Closing the terminal with `ctrl + q` stops the tmux process automatically
- `:rrepl-stop` kills R and cleans up


## Installation and Requirements

