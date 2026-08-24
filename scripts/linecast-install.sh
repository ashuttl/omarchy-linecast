#!/bin/bash
# Install linecast in a terminal the user can watch, from the AUR when yay
# is around (every Omarchy has it) and with uv otherwise. Runs in the
# foreground so the panel can refetch when the window closes.

class="org.omarchy.linecast-install"

if command -v linecast >/dev/null 2>&1; then
  exit 0
fi

script='
if command -v yay >/dev/null 2>&1; then
  echo "Installing linecast from the AUR..."; echo
  yay -S --needed linecast
elif command -v uv >/dev/null 2>&1; then
  echo "Installing linecast with uv..."; echo
  uv tool install linecast
else
  echo "Neither yay nor uv is available. Install linecast by hand:"
  echo "  https://github.com/ashuttl/linecast#install"
fi
echo
if command -v linecast >/dev/null 2>&1; then
  echo "linecast $(linecast --version 2>/dev/null | awk "{print \$2}") is installed. Setting your location from your IP..."
  linecast location auto >/dev/null 2>&1 || true
fi
read -rp "Press Enter to close. "
'

# Float it if Hyprland lets us; a tiled window is fine too.
hyprctl eval "hl.dispatch(hl.dsp.exec_cmd(\"[float; size 900 560; center] true\"))" >/dev/null 2>&1
exec xdg-terminal-exec --app-id="$class" --title="Install linecast" -e bash -c "$script"
