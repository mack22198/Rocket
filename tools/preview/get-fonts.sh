#!/bin/sh
# Downloads open-source copies of the fonts Roblox uses (Fredoka One, Luckiest Guy, Bangers, Oswald, Nunito,
# Denk One, Titillium Web) - plus Montserrat, which stands in for Gotham - so ui.html can draw text the way the game
# does. Run once from tools/preview:  sh get-fonts.sh   (without them the preview falls back to plain fonts)
set -e
mkdir -p fonts
cd fonts
base=https://raw.githubusercontent.com/google/fonts/main
get() { curl -sSfL -o "$2" "$base/$1"; }
get "apache/luckiestguy/LuckiestGuy-Regular.ttf" LuckiestGuy-Regular.ttf
get "ofl/fredoka/Fredoka%5Bwdth,wght%5D.ttf" "Fredoka[wdth,wght].ttf"
get "ofl/bangers/Bangers-Regular.ttf" Bangers-Regular.ttf
get "ofl/montserrat/Montserrat%5Bwght%5D.ttf" "Montserrat[wght].ttf"
get "ofl/oswald/Oswald%5Bwght%5D.ttf" "Oswald[wght].ttf"
get "ofl/nunito/Nunito%5Bwght%5D.ttf" "Nunito[wght].ttf"
get "ofl/denkone/DenkOne-Regular.ttf" DenkOne-Regular.ttf
get "ofl/titilliumweb/TitilliumWeb-Bold.ttf" TitilliumWeb-Bold.ttf
echo "fonts ready"
