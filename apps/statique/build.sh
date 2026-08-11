#!/usr/bin/env bash
# Produit dist/site/ : une application web installable, autonome.
# La bibliotheque Supabase est integree a la page plutot que chargee depuis un
# CDN — l'application ne depend que du projet Supabase lui-meme.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE="../web/node_modules/@supabase/supabase-js/dist/umd/supabase.js"
if [ ! -f "$BUNDLE" ]; then
  echo "Bibliotheque introuvable. Lancez d'abord : (cd ../web && npm install)" >&2
  exit 1
fi

rm -rf dist/site && mkdir -p dist/site
python3 src/icones.py
cp src/manifest.webmanifest src/_headers dist/site/

# Les APK voyagent avec le site : une seule adresse a donner aux ouvriers, et
# rien a deposer nulle part — le site se publie tout seul a chaque poussee.
#
#   2pgpointage.apk           Capacitor, l'application web dans une enveloppe
#   2pgpointage-flutter.apk   Flutter, vraiment native — arm64, les telephones
#                             d'aujourd'hui
#   ...-32bits.apk            pour un appareil ancien qui refuserait le premier
for src in ../natif/2pgpointage.apk \
           ../flutter/2pgpointage-flutter.apk \
           ../flutter/2pgpointage-flutter-32bits.apk; do
  [ -f "$src" ] || continue
  cp "$src" dist/site/
  echo "  $(basename "$src")  $(du -m "$src" | cut -f1) Mo"
done

# Date de fabrication : inscrite dans la page ET dans le nom du cache du
# service worker. Sans elle, un ancien depot reste servi depuis le cache sans
# qu'on puisse le distinguer du nouveau.
VERSION="$(date -u +%Y-%m-%d.%H%M)"
sed "s/__VERSION__/$VERSION/g" src/sw.js > dist/site/sw.js

python3 - "$BUNDLE" "$VERSION" <<'PY'
import sys, pathlib
bundle = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
src = pathlib.Path('src/app.html').read_text(encoding='utf-8')
marqueur = '<!-- INJECTION:supabase-js -->'
if marqueur not in src:
    raise SystemExit('marqueur INJECTION:supabase-js absent de la source')
if '__VERSION__' not in src:
    raise SystemExit('marqueur __VERSION__ absent de la source')
out = src.replace(marqueur, '<script>\n' + bundle + '\n</script>')
out = out.replace('__VERSION__', sys.argv[2])
pathlib.Path('dist/site/index.html').write_text(out, encoding='utf-8')
print(f"  index.html  {len(out)//1024} Ko  (version {sys.argv[2]})")
PY

# Copie a plat, pour ceux qui preferent un seul fichier sans installation.
cp dist/site/index.html dist/tableau-de-bord.html
echo "dist/site/ pret a deposer"
