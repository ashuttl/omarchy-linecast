#!/bin/bash
# Install linecast in a floating terminal the user can watch: from the AUR
# when yay is around (every Omarchy has it), with uv otherwise. Blocks
# until that window closes, so the panel can refetch the moment it's done.

class="org.omarchy.linecast-install"

if command -v linecast >/dev/null 2>&1; then
  exit 0
fi

body=$(mktemp --suffix=.sh)
cat >"$body" <<'INNER'
if command -v yay >/dev/null 2>&1; then
  echo "Installing linecast from the AUR (a minute or two; it builds a small Python package)."; echo
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
  echo "linecast $(linecast --version 2>/dev/null | awk '{print $2}') is installed. Setting your location from your IP..."
  linecast location auto >/dev/null 2>&1 || true
  echo "Done. The bar will fill in when this window closes."
fi
echo
read -rp "Press Enter to close. "
INNER
chmod +x "$body"

cmd="xdg-terminal-exec --app-id=$class --title=linecast -e bash $body"
rules="[float; size 900 560; center]"

# Float it through Hyprland (0.56+ Lua form, then the plain form); fall
# back to running the terminal right here, tiled.
if hyprctl eval "hl.dispatch(hl.dsp.exec_cmd(\"$rules $cmd\"))" >/dev/null 2>&1 \
  || hyprctl dispatch exec "$rules $cmd" >/dev/null 2>&1; then
  # Wait for the window to appear, then for it to go.
  for _ in $(seq 1 40); do
    hyprctl clients -j | jq -e --arg c "$class" 'any(.[]; .class == $c)' >/dev/null 2>&1 && break
    sleep 0.25
  done
  while hyprctl clients -j | jq -e --arg c "$class" 'any(.[]; .class == $c)' >/dev/null 2>&1; do
    sleep 1
  done
else
  xdg-terminal-exec --app-id="$class" --title=linecast -e bash "$body"
fi
rm -f "$body"
