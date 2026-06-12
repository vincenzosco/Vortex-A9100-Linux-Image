#!/bin/sh
# .xinitrc - X11 startup for Vortex86 A9100
#
# This is sourced by xinit/startx to launch the window manager
# and any autostart applications.

# Set a nice background
xsetroot -solid '#1a1a2e'

# Set keyboard repeat rate (adjust if too slow on 300MHz CPU)
xset r rate 300 40

# Disable screen saver
xset s off
xset -dpms

# Start the panel/taskbar (tint2 for lightweight panel, or use fbpanel)
# If available, uncomment below:
# tint2 &

# Start the window manager
exec openbox-session
