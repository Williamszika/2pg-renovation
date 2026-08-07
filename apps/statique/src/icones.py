#!/usr/bin/env python3
"""
Genere les icones de l'application, sans dependance externe.

Pillow n'est pas installe et aucun convertisseur d'image non plus : on encode
donc le PNG a la main. C'est 40 lignes, et ca evite d'ajouter une dependance
lourde pour deux fichiers qui ne changeront jamais.

Dessin : « 2PG » en blanc sur le bleu outremer de l'application, avec la marge
de securite exigee par les icones maskable (le systeme peut rogner jusqu'a 20 %
sur chaque bord pour appliquer sa propre forme).
"""
import struct, zlib, pathlib

FOND = (0x2E, 0x3F, 0xA3)
TRAIT = (0xFF, 0xFF, 0xFF)

# Chiffres et lettres en 5x7, dessines a la main. Suffisant pour « 2PG ».
GLYPHES = {
    "2": ["11110", "00001", "00001", "01110", "10000", "10000", "11111"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
}


def png(largeur, hauteur, pixels):
    """Encode un PNG 8 bits RVB sans compression avec perte."""
    lignes = b"".join(
        b"\x00" + b"".join(struct.pack("BBB", *pixels[y][x]) for x in range(largeur))
        for y in range(hauteur)
    )

    def bloc(typ, data):
        c = typ + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    return (
        b"\x89PNG\r\n\x1a\n"
        + bloc(b"IHDR", struct.pack(">IIBBBBB", largeur, hauteur, 8, 2, 0, 0, 0))
        + bloc(b"IDAT", zlib.compress(lignes, 9))
        + bloc(b"IEND", b"")
    )


def icone(taille, maskable):
    px = [[FOND] * taille for _ in range(taille)]

    # Une icone maskable garde son dessin dans le cercle interieur : le systeme
    # rogne jusqu'a 20 % de chaque bord pour lui appliquer sa propre forme.
    zone = taille * (0.56 if maskable else 0.68)
    texte = "2PG"
    cols = len(texte) * 5 + (len(texte) - 1)   # 1 colonne d'espace entre glyphes
    unite = max(1, int(zone / cols))
    largeur_texte = cols * unite
    hauteur_texte = 7 * unite
    x0 = (taille - largeur_texte) // 2
    y0 = (taille - hauteur_texte) // 2

    for i, ch in enumerate(texte):
        g = GLYPHES[ch]
        dx = x0 + i * 6 * unite
        for ly, ligne in enumerate(g):
            for lx, bit in enumerate(ligne):
                if bit != "1":
                    continue
                for a in range(unite):
                    for b in range(unite):
                        x, y = dx + lx * unite + a, y0 + ly * unite + b
                        if 0 <= x < taille and 0 <= y < taille:
                            px[y][x] = TRAIT
    return png(taille, taille, px)


if __name__ == "__main__":
    sortie = pathlib.Path("dist/site")
    sortie.mkdir(parents=True, exist_ok=True)
    for taille, maskable, nom in [
        (192, False, "icone192.png"),
        (512, False, "icone512.png"),
        (512, True, "iconemaskable512.png"),
        (180, False, "appletouchicon.png"),
    ]:
        chemin = sortie / nom
        chemin.write_bytes(icone(taille, maskable))
        print(f"  {nom}  {chemin.stat().st_size} octets")
