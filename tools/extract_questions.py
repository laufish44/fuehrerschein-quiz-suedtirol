"""Extract the ministerial A/B question list (German + Italian PDF) into app assets.

The PDFs use the base-14 fonts with WinAnsiEncoding; common extractors lose the
umlauts/accents, so this script reads the page content streams directly.

Usage:
    python tools/extract_questions.py <german.pdf> <italian.pdf> <out_dir>

Writes <out_dir>/data/questions.json and <out_dir>/img/<hash>.webp
"""

import hashlib
import io
import json
import re
import sys
from pathlib import Path

import pymupdf
from PIL import Image

# Official chapter order of the ministerial programme (argomenti 1-25), matched
# by the start of the Italian heading text in the PDF.
CHAPTERS = [
    ("Definizioni stradali e di traffico", "Definitionen von Straße und Verkehr, Fahrzeugarten, Pflichten des Fahrers"),
    ("Segnali di pericolo", "Gefahrenzeichen"),
    ("Segnali di divieto", "Verbotszeichen"),
    ("Segnali di obbligo", "Gebotszeichen"),
    ("Segnali di precedenza", "Vorfahrtszeichen"),
    ("Segnaletica orizzontale", "Bodenmarkierungen und Markierungen an Hindernissen"),
    ("Segnalazioni semaforiche", "Ampeln und Zeichen der Verkehrspolizei"),
    ("Segnali di indicazione", "Hinweiszeichen"),
    ("Segnali complementari", "Zusätzliche Zeichen, vorübergehende Zeichen und Baustellen"),
    ("Pannelli integrativi", "Zusatztafeln"),
    ("Limiti di velocit", "Geschwindigkeit, Gefährdung und Behinderung, Bahnübergänge"),
    ("Distanza di sicurezza", "Sicherheitsabstand"),
    ("Norme sulla circol", "Verkehrsregeln: Fahrbahnposition, Abbiegen, Kreuzungen, Einsatzfahrzeuge"),
    ("Esempi di precedenza", "Vorfahrt an Kreuzungen (Beispiele)"),
    ("Norme sul sorpasso", "Überholen"),
    ("Fermata, sosta", "Halten, Parken, Anhalten und Anfahren"),
    ("Ingombro della carreggiata", "Liegenbleiben, Warnzeichen, Autobahn und Schnellstraßen"),
    ("Uso delle luci", "Beleuchtung, Hupe, Kontrollleuchten und Symbole"),
    ("Dispositivi di equipaggiamento", "Ausrüstung: Gurte, Kindersitze, Helm, Schutzkleidung"),
    ("Patenti di guida", "Führerschein, Fahrzeugpapiere, Kontrollen, Strafen, Punkteführerschein"),
    ("Comportamenti per prevenire", "Unfallvermeidung und Verhalten bei Unfällen"),
    ("Guida in relazione alle qualit", "Fahrtüchtigkeit: Alkohol, Drogen, Medikamente, Erste Hilfe"),
    ("Responsabilit", "Haftung und Versicherung (Kfz-Haftpflicht)"),
    ("Limitazione dei consumi", "Verbrauch, Umweltschutz und Verschmutzung"),
    ("Elementi costitutivi del veicolo", "Fahrzeugtechnik, Wartung, Fahrstabilität und vorsichtiges Fahren"),
]

TOKEN_RE = re.compile(rb"\s*(?:(\()|(/[^\s/\[\]()<>]+)|([-+]?\d*\.?\d+)|([A-Za-z\'\"*]+)|(\[|\])|(<<|>>)|(<[0-9A-Fa-f\s]*>))")


def read_string(data, i):
    """Parse a PDF literal string starting after '(' at index i. Returns (bytes, new_index)."""
    out = bytearray()
    depth = 1
    while i < len(data):
        c = data[i]
        if c == 0x5C:  # backslash
            i += 1
            e = data[i]
            esc = {ord("n"): 10, ord("r"): 13, ord("t"): 9, ord("b"): 8, ord("f"): 12}
            if e in esc:
                out.append(esc[e])
                i += 1
            elif 0x30 <= e <= 0x37:
                j = i
                while j < len(data) and j < i + 3 and 0x30 <= data[j] <= 0x37:
                    j += 1
                out.append(int(data[i:j], 8) & 0xFF)
                i = j
            elif e in (10, 13):
                i += 1
                if e == 13 and i < len(data) and data[i] == 10:
                    i += 1
            else:
                out.append(e)
                i += 1
            continue
        if c == 0x28:
            depth += 1
        elif c == 0x29:
            depth -= 1
            if depth == 0:
                return bytes(out), i + 1
        out.append(c)
        i += 1
    raise ValueError("unterminated string")


def tokens(data):
    i = 0
    n = len(data)
    while i < n:
        m = TOKEN_RE.match(data, i)
        if not m:
            i += 1
            continue
        if m.group(1):
            s, i = read_string(data, m.end())
            yield ("str", s.decode("cp1252", errors="replace"))
            continue
        i = m.end()
        if m.group(2):
            yield ("name", m.group(2)[1:].decode("latin-1"))
        elif m.group(3):
            yield ("num", float(m.group(3)))
        elif m.group(4):
            yield ("op", m.group(4).decode("latin-1"))
        # arrays / dicts / hex strings are not used for content we need


def page_items(content):
    """Yield events in stream order: ('text', x, y, font, s) and ('img', x, y, w, h, name)."""
    stack = []
    font = None
    lx = ly = 0.0
    cm = None
    cm_stack = []
    for kind, val in tokens(content):
        if kind != "op":
            stack.append(val)
            continue
        op = val
        if op == "BT":
            lx = ly = 0.0
        elif op == "Td":
            lx += stack[-2]
            ly += stack[-1]
        elif op == "Tm":
            lx, ly = stack[-2], stack[-1]
        elif op == "Tf":
            font = stack[-2]
        elif op == "Tj":
            yield ("text", lx, ly, font, stack[-1])
        elif op == "q":
            cm_stack.append(cm)
        elif op == "Q":
            cm = cm_stack.pop() if cm_stack else None
        elif op == "cm":
            cm = stack[-6:]
        elif op == "Do":
            if cm:
                a, b, c, d, e, f = cm
                yield ("img", e, f, a, d, stack[-1])
        stack.clear()


def join_lines(lines):
    text = ""
    for line in lines:
        line = line.strip()
        if not text:
            text = line
        elif text.endswith("-") and not text.endswith(" -"):
            text += line
        else:
            text += " " + line
    return re.sub(r"\s+", " ", text).strip()


def chapter_of(heading):
    for idx, (prefix, _) in enumerate(CHAPTERS, start=1):
        if heading.startswith(prefix):
            return idx
    raise ValueError(f"unknown chapter heading: {heading!r}")


def parse_pdf(path, extract_images=False, img_dir=None):
    doc = pymupdf.open(path)
    rows = []  # dicts: id, text, answer, group, image(hash)
    groups = {}  # quesito id -> chapter
    current_group = None
    image_cache = {}  # xref -> hash
    for page in doc:
        name_to_xref = {}
        for info in page.get_images(full=True):
            name_to_xref[info[7]] = (info[0], info[1])
        events = list(page_items(page.read_contents()))

        # Headings (with y position) for group assignment.
        headings = []
        heading = None
        for ev in events:
            if ev[0] != "text":
                continue
            _, x, y, font, s = ev
            if font == "F2" and abs(x - 20) < 1 and s.startswith("Quesito n"):
                m = re.match(r"Quesito n\S*\s+(\d+)\s+-\s+(.*)", s)
                heading = {"id": int(m.group(1)), "y": y, "parts": [m.group(2)]}
                headings.append(heading)
            elif heading is not None and font == "F2" and abs(x - 20) < 1:
                heading["parts"].append(s)
            elif font == "F3":
                heading = None
        for h in headings:
            groups[h["id"]] = chapter_of(join_lines(h["parts"]))

        def group_for(y):
            above = [h for h in headings if h["y"] > y]
            if above:
                return min(above, key=lambda h: h["y"])["id"]
            return current_group

        row = None
        for ev in events:
            if ev[0] == "text":
                _, x, y, font, s = ev
                if font != "F4":
                    continue
                if abs(x - 22) < 1 and re.fullmatch(r"\d{4,6}", s.strip()):
                    row = {"id": int(s), "lines": [], "answer": None, "image": None, "group": group_for(y)}
                    rows.append(row)
                elif abs(x - 77.5) < 1 and row is not None:
                    row["lines"].append(s)
                elif abs(x - 355) < 1 and row is not None and s.strip() in ("VERO", "FALSO"):
                    row["answer"] = s.strip() == "VERO"
            elif ev[0] == "img" and row is not None:
                _, x, y, w, h, name = ev
                if abs(x - 465.63) > 1:
                    continue  # ministry logo
                xref, smask = name_to_xref[name]
                if extract_images:
                    if xref not in image_cache:
                        image_cache[xref] = save_image(doc, xref, smask, img_dir)
                    row["image"] = image_cache[xref]
                else:
                    row["image"] = True
        if headings:
            current_group = min(headings, key=lambda h: h["y"])["id"]
    doc.close()
    for r in rows:
        r["text"] = join_lines(r.pop("lines"))
    return rows, groups


def save_image(doc, xref, smask, img_dir):
    pix = pymupdf.Pixmap(doc, xref)
    if smask:
        mask = pymupdf.Pixmap(doc, smask)
        pix = pymupdf.Pixmap(pix, mask)
    if pix.colorspace and pix.colorspace.n not in (1, 3):
        pix = pymupdf.Pixmap(pymupdf.csRGB, pix)
    png = pix.tobytes("png")
    img = Image.open(io.BytesIO(png))
    img.load()
    digest = hashlib.sha1(img.tobytes() + str(img.size).encode() + img.mode.encode()).hexdigest()[:12]
    out = img_dir / f"{digest}.webp"
    if not out.exists():
        if img.mode not in ("RGB", "RGBA", "L", "LA"):
            img = img.convert("RGBA")
        img.save(out, "WEBP", lossless=True, method=6)
    return digest


def main():
    de_pdf, it_pdf, out_dir = sys.argv[1:4]
    out = Path(out_dir)
    img_dir = out / "img"
    data_dir = out / "data"
    img_dir.mkdir(parents=True, exist_ok=True)
    data_dir.mkdir(parents=True, exist_ok=True)

    de_rows, de_groups = parse_pdf(de_pdf, extract_images=True, img_dir=img_dir)
    it_rows, it_groups = parse_pdf(it_pdf)
    it_by_id = {r["id"]: r for r in it_rows}

    problems = []
    questions = []
    group_order = []
    group_images = {}
    for r in de_rows:
        it = it_by_id.get(r["id"])
        if it is None:
            problems.append(f"{r['id']}: missing in Italian PDF")
        elif it["answer"] != r["answer"]:
            problems.append(f"{r['id']}: answer differs DE={r['answer']} IT={it['answer']}")
        elif it["group"] != r["group"]:
            problems.append(f"{r['id']}: group differs DE={r['group']} IT={it['group']}")
        if r["answer"] is None or r["group"] is None or not r["text"]:
            problems.append(f"{r['id']}: incomplete row {r}")
        g = r["group"]
        if g not in group_images:
            group_images[g] = []
            group_order.append(g)
        if r["image"] and r["image"] not in group_images[g]:
            group_images[g].append(r["image"])
        questions.append({
            "id": r["id"],
            "g": g,
            "a": r["answer"],
            "de": r["text"],
            "it": it["text"] if it else None,
            **({"img": r["image"]} if r["image"] else {}),
        })
    extra_it = set(it_by_id) - {r["id"] for r in de_rows}
    if extra_it:
        problems.append(f"only in Italian PDF: {sorted(extra_it)[:20]} ({len(extra_it)})")

    data = {
        "source": Path(de_pdf).name,
        "chapters": [
            {"id": i, "it": it_name, "de": de_name}
            for i, (it_name, de_name) in enumerate(CHAPTERS, start=1)
        ],
        "groups": [
            {"id": g, "ch": de_groups[g], **({"img": group_images[g]} if group_images[g] else {})}
            for g in group_order
        ],
        "questions": questions,
    }
    with open(data_dir / "questions.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))

    per_ch = {}
    for g in data["groups"]:
        per_ch.setdefault(g["ch"], [0, 0])[0] += 1
    for q in questions:
        per_ch[de_groups[q["g"]]][1] += 1
    print(f"questions: {len(questions)}  groups: {len(data['groups'])}  images: {len(list(img_dir.glob('*.webp')))}")
    for ch in sorted(per_ch):
        print(f"  ch {ch:2d}: {per_ch[ch][0]:4d} groups {per_ch[ch][1]:5d} questions  {CHAPTERS[ch-1][1]}")
    multi = [g for g in data["groups"] if len(g.get("img", [])) > 1]
    print(f"groups with >1 distinct image: {len(multi)}")
    print(f"problems: {len(problems)}")
    for p in problems[:40]:
        print("  ", p)


if __name__ == "__main__":
    main()
