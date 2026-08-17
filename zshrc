export ZSH="${HOME}/.oh-my-zsh"

export LANG=en_US.UTF-8  
export LANGUAGE=en_US:en  
export LC_ALL=en_US.UTF-8

export CLICOLOR_FORCE=1
export TERM=xterm-256color

ZSH_THEME="simple"

CASE_SENSITIVE="true"

plugins=(git
         zsh-interactive-cd
         vi-mode
         alias-finder
         command-not-found
         extract
         history-substring-search
         zsh-syntax-highlighting
         zsh-autosuggestions
         )

source ${ZSH}/oh-my-zsh.sh

export EDITOR='nvim'
export VIEWER='nvim'

export PATH=${HOME}/.local/bin:${PATH}

export PATH=/usr/local/go/bin:${PATH}
export GOPATH=${HOME}/go
export PATH=${PATH}:${GOPATH}/bin

# Add cargo binaries to PATH
export PATH=${HOME}/.cargo/bin:${PATH}

# pperf
export PATH=/usr/local/go/pkg/tool/linux_amd64/:${PATH}

# claude
export PATH=${HOME}/.claude/local/:${PATH}

# npm globals installed here survive container recreation (host bind mount)
export NPM_CONFIG_PREFIX=${HOME}/.npm-global
export PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}

alias codex-update='npm install -g @openai/codex@latest'

if [ ! -x "${NPM_CONFIG_PREFIX}/bin/codex" ]; then
    echo "Installing @openai/codex into ${NPM_CONFIG_PREFIX}..."
    npm install -g @openai/codex
fi

# Docker settings
export DOCKER_HOST=unix:///var/run/docker.sock

# Activate Python virtual environment
source ${HOME}/.venv/bin/activate

function colorize() {
    if [ "$1" = "cut" ]; then
        # Pass the "cut" argument to the script
        python3 ~/.colorize_script.py "cut"
    else
        # Call script without arguments for original behavior
        # If other arguments were passed to colorize (e.g. colorize foo bar),
        # they will be ignored by the script if it's not expecting them.
        # The script currently only checks for "cut" or no arguments.
        python3 ~/.colorize_script.py
    fi
}

sudo chmod 0666 /var/run/docker.sock

export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
