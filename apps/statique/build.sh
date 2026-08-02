#!/usr/bin/env bash
# Produit une page autonome : la bibliotheque Supabase est integree au fichier
# plutot que chargee depuis un CDN, pour que la page ne depende de rien.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE="../web/node_modules/@supabase/supabase-js/dist/umd/supabase.js"
if [ ! -f "$BUNDLE" ]; then
  echo "Bibliotheque introuvable. Lancez d'abord : (cd ../web && npm install)" >&2
  exit 1
fi

mkdir -p dist
python3 - "$BUNDLE" <<'PY'
import sys, pathlib
bundle = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
src = pathlib.Path('src/tableau-de-bord.html').read_text(encoding='utf-8')
marqueur = '<!-- INJECTION:supabase-js -->'
if marqueur not in src:
    raise SystemExit('marqueur INJECTION:supabase-js absent de la source')
out = src.replace(marqueur, '<script>\n' + bundle + '\n</script>')
pathlib.Path('dist/tableau-de-bord.html').write_text(out, encoding='utf-8')
print(f"dist/tableau-de-bord.html  —  {len(out)//1024} Ko")
PY
