if [[ -o interactive ]]; then
  ##### Interactive-only options
  setopt alwaystoend
  setopt autocd
  setopt noautomenu
  setopt autopushd
  setopt noautoremoveslash
  setopt nobeep
  setopt noflowcontrol
  setopt globdots
  setopt interactivecomments
  setopt nolisttypes
  setopt promptsubst

  ##### History
  export HISTFILE="${HISTFILE:-$HOME/.local/state/zsh/history}"
  export HISTSIZE=${HISTSIZE:-200000}
  export SAVEHIST=${SAVEHIST:-200000}
  setopt extendedhistory
  setopt histexpiredupsfirst histfindnodups histignoredups histsavenodups histverify
  setopt histignorespace
  setopt sharehistory
  setopt incappendhistory
  setopt histfcntllock

  # free Ctrl-S from XON/XOFF
  [[ -t 1 ]] && stty -ixon

  ##### Atuin (history search) — installed at runtime if present
  if command -v atuin &>/dev/null; then
    eval "$(atuin init zsh)"

    _atuin_search_global () {
      emulate -L zsh
      zle -I
      local output
      output=$(ATUIN_SHELL_ZSH=t ATUIN_LOG=error ATUIN_QUERY=$BUFFER atuin search --filter-mode=global $* -i 3>&1 1>&2 2>&3)
      zle reset-prompt
      if [[ -n $output ]]; then
        RBUFFER=""
        LBUFFER=$output
        if [[ $LBUFFER == __atuin_accept__:* ]]; then
          LBUFFER=${LBUFFER#__atuin_accept__:}
          zle accept-line
        fi
      fi
    }
    zle -N _atuin_search_global

    bindkey '^R' atuin-search
    bindkey '^S' _atuin_search_global
  else
    # Fallback: plain history search
    bindkey '^R' history-incremental-search-backward
  fi

  ##### Keymap & terminfo-safe keybindings
  bindkey -e
  autoload -Uz zkbd || true
  [[ -n ${terminfo[kcuu1]} ]] && bindkey "${terminfo[kcuu1]}" up-line-or-history
  [[ -n ${terminfo[kcud1]} ]] && bindkey "${terminfo[kcud1]}" down-line-or-history
  [[ -n ${terminfo[kcub1]} ]] && bindkey "${terminfo[kcub1]}" backward-char
  [[ -n ${terminfo[kcuf1]} ]] && bindkey "${terminfo[kcuf1]}" forward-char
  [[ -n ${terminfo[kdch1]} ]] && bindkey "${terminfo[kdch1]}" delete-char
  [[ -n ${terminfo[khome]} ]] && bindkey "${terminfo[khome]}" beginning-of-line
  [[ -n ${terminfo[kend]}  ]] && bindkey "${terminfo[kend]}"  end-of-line

  bindkey '^?' backward-delete-char
  bindkey '^A' beginning-of-line
  bindkey '^E' end-of-line

  ##### fzf-tab (fuzzy completion UI)
  zinit light Aloxaf/fzf-tab
  zstyle ':completion:*' menu no
  zstyle ':completion:*' list-colors '=*=0'
  zstyle ':fzf-tab:*' switch-group 'ctrl-h' 'ctrl-l'
  zstyle ':fzf-tab:*' default-color ''
fi
