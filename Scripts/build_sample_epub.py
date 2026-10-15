#!/usr/bin/env python3
"""Builds the bundled sample book "On Reading Slowly" (EPUB 3 with EPUB 2 NCX fallback).

Usage: python3 Scripts/build_sample_epub.py <repo-root>
"""
import os
import sys
import zipfile
from html import escape

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
SRC = os.path.join(ROOT, "Scripts", "SampleBook")
OUT = os.path.join(ROOT, "Quolia", "Resources", "On Reading Slowly.epub")

TITLE = "On Reading Slowly"
AUTHOR = "Quolia Editions"

# Original text written for Quolia. Paragraphs may contain <em> and <strong>.
CHAPTERS = [
    ("The Quiet Hour", [
        "There is an hour in most days that belongs to no one. It arrives early, before the messages begin, or late, after the last of them has been answered. It is easy to miss, because it does not announce itself. It simply waits, the way a chair waits by a window.",
        "For a long time I filled that hour with whatever was nearest: a feed, a headline, the small bright noise of other people's days. I told myself it was rest. It was not rest. It was a kind of weather passing through me, and when it was gone I could not have said what it had been about.",
        "Reading slowly began as an experiment in giving that hour a shape. One book, one chair, no plan beyond the next page. The first week was uncomfortable. My attention kept reaching for something to hold, the way a hand reaches for a phone that is not in the pocket. By the second week the reaching grew quieter. By the third I noticed that I could remember what I had read the day before, and the day before that.",
        "<em>Attention is not a resource we spend; it is a place we live.</em> When it is scattered, we are scattered with it. When it settles on a sentence long enough for the sentence to settle back, something changes in the reader. The book stops being a container of information and becomes a conversation that continues after it is closed.",
        "I do not think speed is the enemy. There are books meant to be crossed quickly, like bridges. But most of the books I love were built to be walked through, room by room, and they reward the reader who lingers in the doorways.",
        "So I keep the quiet hour now. Some days it is twenty minutes, some days only ten. It is never wasted, even when I read a single page, because the page stays with me. That is the whole trick, if there is one: read less at a time, and keep more of it.",
    ]),
    ("Marginalia", [
        "The best books I own are the ones I have written in. Not much, and never neatly — a line beside a paragraph, a question mark, a single word that meant something to me at the time and now reads like a message from a stranger who happened to share my handwriting.",
        "Marginalia are a record of a meeting. The author spoke, and the reader, for once, answered. Most reading is a monologue; the margin is where it turns into a dialogue.",
        "When I began reading on screens, I lost the margin and did not notice the loss for years. Highlights were possible, but they collected in a list somewhere, divorced from the moment they were made. A highlight without a thought beside it is like a bookmark without a book: it tells you that something mattered, not why.",
        "The note is the why. It does not need to be clever. <em>“This is what my grandmother meant.”</em> <em>“Disagree — but why?”</em> <em>“Read this again in a year.”</em> These small sentences are the threads by which a book is woven into a life.",
        "I have started to think of my notes as a second book, written slowly alongside the first. It has no plot and no audience. It is made of the moments when reading turned into thinking. Every so often I page through it and find that it knows me better than I expected.",
        "If you take one practice from these essays, let it be this: when a sentence stops you, stay stopped. Mark it. Then write one honest line about why. You will be surprised by who you were when you come back to it.",
    ]),
    ("The Art of Forgetting", [
        "We forget most of what we read. This is not a failure of character; it is how memory works. The mind is not a library but a garden, and gardens are shaped as much by what is cleared away as by what is planted.",
        "Still, it is strange to finish a book that moved you and, a year later, be able to recall only its color, or the room you read it in, or a single image that has detached from everything around it. Where did the rest go?",
        "Some of it went nowhere. It became part of how you see. The argument you can no longer reconstruct has quietly adjusted your instincts; the character whose name you have lost still walks beside you in certain moods. Reading changes us even when it does not stay with us as content.",
        "But some of it is simply gone, and some of that we would like back. Here the old remedy is the best one: return. A passage revisited after a week, then a month, then a season, has a way of putting down roots. Each return is shorter than the last and holds a little longer.",
        "<strong>Forgetting is the soil; remembering is what grows when we return.</strong> The goal is not to keep everything — that would be unbearable — but to choose a few things worth keeping and to visit them often enough that they become ours.",
        "This is why I let old highlights find me again. Not as homework, and not on a schedule I have to manage, but the way a friend mentions something you said years ago and you realize you still believe it. A thought revisited becomes a thought kept.",
    ]),
    ("Rereading", [
        "The first time through a book, we read for what happens. The second time, we read for how it happens. By the third, we are reading ourselves — noticing what we noticed before, and what we missed, and what has changed in the years between.",
        "Rereading has an undeserved reputation for being a waste of time, as if there were a finite number of books and we were behind on them. There are more good books than any life can hold. Choosing to return to one is not a failure to keep up; it is a decision about depth.",
        "A book reread is never the same book. The words have not moved, but the reader has. A novel I found cold at twenty felt tender at thirty-five. An essay I underlined fiercely in one decade made me wince in the next, and then, in the decade after that, I underlined it again for different reasons.",
        "There is a particular pleasure in reaching a passage you remember and feeling it arrive like a familiar street. You know what is around the corner, and knowing makes you slow down rather than speed up. You look at the windows this time.",
        "I keep a short shelf of books I return to. It changes slowly. A book earns its place there not by being the best I have read, but by being the one that seems to have more to say each time I come back to it.",
        "If you have a book like that, read it again this year. Read it slowly. Mark what is new. Then put it back on the shelf and let it wait for the next version of you.",
    ]),
    ("A Library of One", [
        "Every reader builds a library, whether or not it sits on shelves. It is made of the books we have finished and abandoned, the passages we copied out, the notes in the margins, the sentences we can still recite. It is the shape our reading has left in us.",
        "For most of history this library was invisible. It lived in memory and in a few worn volumes. Now it can live alongside us, searchable and portable, and that is a gift — as long as we remember that the point was never the collection. The point was the attention that made it.",
        "A good personal library is not large. It is <em>legible</em>. You can walk through it and recognize yourself at different ages. You can find the quotation you half-remember in a few seconds instead of a few hours. You can open it on a difficult day and be reminded of what you once found steadying.",
        "Build it slowly. Highlight less than you think you should, and write more beside what you highlight. Let books you will never return to go. Keep the ones that keep you.",
        "And make room for quiet. The library of one is not a monument; it is a practice, renewed in small hours by a reader in a chair, turning one more page, stopping when a sentence asks to be stopped for.",
        "That is all reading slowly has ever meant to me: to read in a way that lets the book stay. Read. Highlight. Remember. Then, someday, read it again.",
    ]),
]

CSS = """body { font-family: serif; line-height: 1.5; margin: 0 5%; }
h1 { font-size: 1.6em; margin: 2em 0 1em; }
p { margin: 0 0 0.8em; }
.ornament { text-align: center; margin: 1.5em 0; }
"""


def xhtml(title, body):
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en">
<head><meta charset="utf-8"/><title>{escape(title)}</title><link rel="stylesheet" type="text/css" href="../styles.css"/></head>
<body>
{body}
</body>
</html>
"""


def build():
    files = {}
    files["META-INF/container.xml"] = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
"""
    files["OEBPS/styles.css"] = CSS
    files["OEBPS/text/cover.xhtml"] = xhtml(TITLE, '<div><img src="../images/cover.jpg" alt="Cover"/></div>')

    manifest = [
        '<item id="css" href="styles.css" media-type="text/css"/>',
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
        '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
        '<item id="cover-image" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>',
        '<item id="cover" href="text/cover.xhtml" media-type="application/xhtml+xml"/>',
    ]
    spine = ['<itemref idref="cover" linear="yes"/>']
    nav_items = []
    ncx_points = []

    for index, (title, paragraphs) in enumerate(CHAPTERS, start=1):
        name = f"chapter{index}.xhtml"
        body = [f'<section epub:type="chapter"><h1>{escape(title)}</h1>']
        for i, paragraph in enumerate(paragraphs):
            if i == len(paragraphs) // 2 and index % 2 == 1:
                body.append('<hr class="ornament"/>')
            body.append(f"<p>{paragraph}</p>")
        body.append("</section>")
        files[f"OEBPS/text/{name}"] = xhtml(title, "\n".join(body))
        manifest.append(f'<item id="ch{index}" href="text/{name}" media-type="application/xhtml+xml"/>')
        spine.append(f'<itemref idref="ch{index}"/>')
        nav_items.append(f'<li><a href="text/{name}">{escape(title)}</a></li>')
        ncx_points.append(
            f'<navPoint id="np{index}" playOrder="{index}"><navLabel><text>{escape(title)}</text></navLabel>'
            f'<content src="text/{name}"/></navPoint>'
        )

    files["OEBPS/nav.xhtml"] = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><meta charset="utf-8"/><title>Contents</title></head>
<body><nav epub:type="toc" id="toc"><h1>Contents</h1><ol>{''.join(nav_items)}</ol></nav></body>
</html>
"""
    files["OEBPS/toc.ncx"] = f"""<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head><meta name="dtb:uid" content="urn:uuid:4f9b1d2e-quolia-sample"/></head>
<docTitle><text>{escape(TITLE)}</text></docTitle>
<navMap>{''.join(ncx_points)}</navMap>
</ncx>
"""
    files["OEBPS/content.opf"] = f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:4f9b1d2e-quolia-sample</dc:identifier>
    <dc:title>{escape(TITLE)}</dc:title>
    <dc:creator>{escape(AUTHOR)}</dc:creator>
    <dc:language>en</dc:language>
    <meta property="dcterms:modified">2026-10-15T00:00:00Z</meta>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    {chr(10).join('    ' + m for m in manifest).strip()}
  </manifest>
  <spine toc="ncx">
    {chr(10).join('    ' + s for s in spine).strip()}
  </spine>
</package>
"""

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with zipfile.ZipFile(OUT, "w") as archive:
        # mimetype must be first and stored uncompressed.
        archive.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        for path, text in files.items():
            archive.writestr(path, text, compress_type=zipfile.ZIP_DEFLATED)
        archive.write(os.path.join(SRC, "OEBPS", "images", "cover.jpg"), "OEBPS/images/cover.jpg",
                      compress_type=zipfile.ZIP_STORED)
    print(f"wrote {OUT}")


build()
