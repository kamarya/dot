fpath=(~/.zsh $fpath) 
zstyle ':completion:*:*:git:*' script ~/.zsh/git-completion.bash
autoload -Uz compinit
compinit

# kamary palette (see vim/colors/kamary.vim), mapped by the vim highlight
# group each color actually represents so the prompt reads as one theme
# with vim/tmux instead of an ad-hoc set of ANSI numbers:
#   b9d3ee Identifier   -- username (matches tmux status-style fg)
#   00ffcd CursorLineNr -- success (matches tmux active-window/border accent)
#   ee3a8c PreProc      -- failure (matches tmux bell/alert accent)
#   dad085 Directory    -- path
#   668799 Delimiter    -- prompt arrow
#   888888 Comment      -- right-prompt timestamp
PROMPT='%F{#b9d3ee}%n%f %(?.%F{#00ffcd}⏺.%F{#ee3a8c}⏺)%f %F{#dad085}%2~%f %F{#668799}>%f '
RPROMPT='%F{#888888}⏱ %*%f'



alias ll='ls -alth'

# blinking line (bar) cursor -- set on shell start and again before every
# prompt, since programs like vim change the cursor shape and don't
# always restore it on exit
echo -ne '\e[5 q'
precmd() { echo -ne '\e[5 q' }