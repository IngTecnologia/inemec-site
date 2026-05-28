#!/usr/bin/env python3
"""
Construye el kit de contenido para la reconstruccion del sitio inemec.com.
Lee _full_content.json (export de WordPress) y genera:
  - paginas/*.md y posts/*.md  : texto limpio (sin shortcodes WPBakery, HTML -> markdown)
  - MAPA_DEL_SITIO.md          : estructura de navegacion
  - _media_referenciada.txt    : imagenes referenciadas por cada pagina
"""
import json, re, os, html
from collections import defaultdict

ROOT = os.path.dirname(os.path.abspath(__file__))
data = json.load(open(os.path.join(ROOT, "_full_content.json"), encoding="utf-8"))

# ---------- Limpieza de contenido ----------
def strip_wpbakery(text):
    """Quita shortcodes [vc_*], [rev_slider], etc. — conserva el texto interior."""
    # Remueve shortcodes autocerrados y de apertura/cierre, dejando el contenido
    # Iteramos porque pueden estar anidados
    prev = None
    while prev != text:
        prev = text
        # [shortcode attr="x"] y [/shortcode]
        text = re.sub(r"\[/?[a-zA-Z0-9_]+[^\]]*\]", "", text)
    return text

def html_to_markdown(text):
    """Conversion ligera de HTML a markdown legible."""
    # Enlaces
    text = re.sub(r'<a\s+[^>]*href="([^"]+)"[^>]*>(.*?)</a>', r'[\2](\1)', text, flags=re.DOTALL|re.IGNORECASE)
    # Imagenes
    text = re.sub(r'<img\s+[^>]*src="([^"]+)"[^>]*>', r'![imagen](\1)', text, flags=re.IGNORECASE)
    # Encabezados
    for i in range(1, 7):
        text = re.sub(rf'<h{i}[^>]*>(.*?)</h{i}>', lambda m: "\n" + "#"*i + " " + m.group(1).strip() + "\n", text, flags=re.DOTALL|re.IGNORECASE)
    # Negritas / enfasis
    text = re.sub(r'<(strong|b)[^>]*>(.*?)</\1>', r'**\2**', text, flags=re.DOTALL|re.IGNORECASE)
    text = re.sub(r'<(em|i)[^>]*>(.*?)</\1>', r'*\2*', text, flags=re.DOTALL|re.IGNORECASE)
    # Listas
    text = re.sub(r'<li[^>]*>(.*?)</li>', r'- \1\n', text, flags=re.DOTALL|re.IGNORECASE)
    # Parrafos y saltos
    text = re.sub(r'</p>', '\n\n', text, flags=re.IGNORECASE)
    text = re.sub(r'<br\s*/?>', '\n', text, flags=re.IGNORECASE)
    # Quita cualquier otro tag
    text = re.sub(r'<[^>]+>', '', text)
    # Entidades HTML
    text = html.unescape(text)
    # \n literales del dump
    text = text.replace('\\n', '\n')
    # Limpia espacios excesivos
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()

def extract_media(text):
    """URLs de imagenes/archivos referenciados."""
    urls = re.findall(r'(?:src|image|url)="?(https?://[^"\s\]]+\.(?:jpg|jpeg|png|svg|webp|gif|pdf))"?', text, re.IGNORECASE)
    # tambien las que esten sin comillas en atributos vc
    urls += re.findall(r'(https?://[^"\s\]]+\.(?:jpg|jpeg|png|svg|webp|gif|pdf))', text, re.IGNORECASE)
    return sorted(set(urls))

def slugify(s):
    s = re.sub(r'[^\w\s-]', '', s).strip().lower()
    return re.sub(r'[\s_-]+', '-', s) or "sin-titulo"

# ---------- Generacion ----------
media_by_page = {}
pages = [d for d in data if d["type"] == "page"]
posts = [d for d in data if d["type"] == "post"]

def write_entry(d, subdir):
    title = d["title"] or "(sin titulo)"
    clean = html_to_markdown(strip_wpbakery(d["content"]))
    media = extract_media(d["content"])
    media_by_page[d["slug"] or str(d["id"])] = media
    fname = f"{slugify(d['slug'] or title)}.md"
    path = os.path.join(ROOT, subdir, fname)
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"# {title}\n\n")
        f.write(f"> **Slug:** `/{d['slug']}/`  ·  **ID:** {d['id']}  ·  **Tipo:** {d['type']}\n")
        f.write(f"> **URL original:** {d['url']}\n")
        if d.get("date"):
            f.write(f"> **Fecha:** {d['date']}\n")
        f.write("\n---\n\n")
        if clean:
            f.write(clean + "\n")
        else:
            f.write("_(Pagina sin contenido textual — probablemente construida solo con bloques visuales / slider.)_\n")
        if media:
            f.write(f"\n\n---\n\n### Medios referenciados ({len(media)})\n\n")
            for m in media:
                f.write(f"- {m}\n")
    return fname, len(clean), len(media)

print("=== PAGINAS ===")
for d in sorted(pages, key=lambda x: (x["menu_order"], x["title"])):
    fname, clen, mcount = write_entry(d, "paginas")
    print(f"  {fname:50} {clen:>6} chars, {mcount} medios")

print("\n=== POSTS (blog) ===")
for d in sorted(posts, key=lambda x: x["date"], reverse=True):
    fname, clen, mcount = write_entry(d, "posts")
    print(f"  {fname:50} {clen:>6} chars, {mcount} medios")

# ---------- Mapa del sitio ----------
with open(os.path.join(ROOT, "MAPA_DEL_SITIO.md"), "w", encoding="utf-8") as f:
    f.write("# Mapa del sitio inemec.com\n\n")
    f.write(f"Estructura extraida del WordPress restaurado. {len(pages)} paginas, {len(posts)} posts.\n\n")
    f.write("## Paginas (orden del menu)\n\n")
    for d in sorted(pages, key=lambda x: (x["menu_order"], x["title"])):
        f.write(f"- **{d['title']}** — `/{d['slug']}/` → [{slugify(d['slug'] or d['title'])}.md](paginas/{slugify(d['slug'] or d['title'])}.md)\n")
    f.write("\n## Posts / Blog\n\n")
    for d in sorted(posts, key=lambda x: x["date"], reverse=True):
        f.write(f"- **{d['title']}** — {d['date'][:10]} — `/{d['slug']}/`\n")

# ---------- Media referenciada ----------
with open(os.path.join(ROOT, "_media_referenciada.txt"), "w", encoding="utf-8") as f:
    allm = set()
    for slug, urls in media_by_page.items():
        allm.update(urls)
    f.write(f"# {len(allm)} archivos de media referenciados en el contenido\n\n")
    for m in sorted(allm):
        f.write(m + "\n")

print(f"\nMapa del sitio y catalogo de media generados.")
print(f"Total media referenciada unica: {len(set(m for v in media_by_page.values() for m in v))}")
