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
cp src/manifest.webmanifest src/sw.js dist/site/

python3 - "$BUNDLE" <<'PY'
import sys, pathlib
bundle = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
src = pathlib.Path('src/app.html').read_text(encoding='utf-8')
marqueur = '<!-- INJECTION:supabase-js -->'
if marqueur not in src:
    raise SystemExit('marqueur INJECTION:supabase-js absent de la source')
out = src.replace(marqueur, '<script>\n' + bundle + '\n</script>')
pathlib.Path('dist/site/index.html').write_text(out, encoding='utf-8')
print(f"  index.html  {len(out)//1024} Ko")
PY

# Copie a plat, pour ceux qui preferent un seul fichier sans installation.
cp dist/site/index.html dist/tableau-de-bord.html
echo "dist/site/ pret a deposer"
