# ~/.bashrc - Root shell configuration for Vortex86 A9100

# Source global profile
if [ -f /etc/profile ]; then
    . /etc/profile
fi

# History settings
HISTSIZE=500
HISTFILESIZE=1000

# Prompt with color
export PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
