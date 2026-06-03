#!/usr/bin/env python3
"""
Merge Pantavisor documentation Markdown sources into a single RST file for
Sphinx rendering.  Uses only Python stdlib — no third-party packages required.

Document order follows the link sequence found in each section's index.md.
index.md files are used for ordering only and are never included as content.
A table of contents is emitted after the introductory paragraph.

Internal .md cross-links are resolved to RST :ref: labels so they remain
navigable in the merged document.  External links become RST hyperlinks.
Inline images (including clickable badge images) become RST substitution
references; the substitution definitions are emitted at the top of the file.
Unresolvable references fall back to plain text.

Usage: pantavisor-docs-gen-html.py <staging-dir> <output.rst> [version-str]
"""
import re
import sys
from pathlib import Path

# RST underline chars for Markdown heading levels 1-6.
# Tuple: (char, use_overline)
_HEADING = {
    1: ('*', True),
    2: ('=', False),
    3: ('-', False),
    4: ('~', False),
    5: ('^', False),
    6: ('"', False),
}
_TITLE_CHAR = '='   # used for the merged-document title (with overline)

PANTAVISOR_REPO      = 'https://github.com/pantavisor/pantavisor'
META_PANTAVISOR_REPO = 'https://github.com/pantavisor/meta-pantavisor'


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def slugify(text):
    """Return a valid, stable RST label slug from arbitrary text."""
    text = re.sub(r'[`*_\[\]()\'"<>]+', '', text)
    text = re.sub(r'[^\w\s-]', '', text.lower())
    text = re.sub(r'[\s_-]+', '-', text)
    return text.strip('-') or 'section'


def rst_title(text):
    bar = _TITLE_CHAR * max(len(text.encode()), 4)
    return '{bar}\n{text}\n{bar}'.format(bar=bar, text=text)


def rst_heading(text, md_level, label=None):
    char, overline = _HEADING.get(md_level, ('"', False))
    bar = char * max(len(text.encode()), 4)
    parts = []
    if label:
        parts += ['.. _{}:'.format(label), '']
    if overline:
        parts.append(bar)
    parts += [text, bar]
    return '\n'.join(parts)


def strip_frontmatter(text):
    """Remove YAML front matter delimited by --- ... --- from Markdown."""
    lines = text.splitlines(keepends=True)
    if lines and lines[0].strip() == '---':
        for i, line in enumerate(lines[1:], 1):
            if line.strip() in ('---', '...'):
                return ''.join(lines[i + 1:])
    return text


def image_sub_name(image_subs):
    """Return the next unique substitution name."""
    return 'img-{}'.format(len(image_subs) + 1)


def render_image_subs(image_subs):
    """Emit all RST image substitution definitions."""
    lines = []
    for name, img_url, alt, target in image_subs.values():
        lines.append('.. |{name}| image:: {url}'.format(name=name, url=img_url))
        lines.append('   :alt: {}'.format(alt or name))
        if target:
            lines.append('   :target: {}'.format(target))
        lines.append('')
    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# File collection — follow index.md link order
# ---------------------------------------------------------------------------

def extract_links(index_path):
    """Return ordered list of unique relative link targets from a Markdown file."""
    text = index_path.read_text(encoding='utf-8')
    seen, result = set(), []
    for m in re.finditer(r'\[[^\]]+\]\(([^)#\s]+)\)', text):
        target = m.group(1).strip().lstrip('./')
        if not target or target.startswith(('http', 'mailto', '/')):
            continue
        if target not in seen:
            seen.add(target)
            result.append(target)
    return result


def collect_ordered(directory, _seen=None, _visited_dirs=None):
    """
    Return an ordered list of content .md Paths under directory.

    Reading order is defined by the link sequence in each index.md.
    Files not mentioned in any index are appended alphabetically.
    index.md files are never included in the result.
    """
    if _seen is None:
        _seen = set()          # resolved file paths already collected
    if _visited_dirs is None:
        _visited_dirs = set()  # resolved dir paths already recursed into

    d = Path(directory).resolve()
    if d in _visited_dirs:
        return []
    _visited_dirs.add(d)

    index_file = d / 'index.md'
    refs = extract_links(index_file) if index_file.is_file() else []

    files = []

    def add_file(p):
        rp = p.resolve()
        if rp not in _seen:
            _seen.add(rp)
            files.append(rp)

    def recurse(sub):
        # collect_ordered handles _seen deduplication internally; just extend
        files.extend(collect_ordered(sub, _seen, _visited_dirs))

    # Process references in the order they appear in index.md
    for ref in refs:
        candidate = d / ref
        if candidate.is_dir():
            recurse(candidate)
        elif candidate.is_file() and candidate.suffix == '.md' and candidate.name != 'index.md':
            add_file(candidate)
        else:
            # Try appending .md (links that omit the extension)
            with_ext = d / (ref.rstrip('/') + '.md')
            if with_ext.is_file() and with_ext.name != 'index.md':
                add_file(with_ext)

    # Append unreferenced .md files in this directory alphabetically
    for f in sorted(p for p in d.iterdir()
                    if p.is_file() and p.suffix == '.md' and p.name != 'index.md'):
        add_file(f)

    # Recurse into unreferenced subdirectories alphabetically
    for sub in sorted(p for p in d.iterdir()
                      if p.is_dir() and not p.name.startswith('.')):
        if sub.resolve() not in _visited_dirs:
            recurse(sub)

    return files


# ---------------------------------------------------------------------------
# Markdown → RST conversion
# ---------------------------------------------------------------------------

def inline_rst(text, file_labels, staging, current_file, image_subs):
    """Convert inline Markdown spans to RST, collecting image substitutions."""

    def resolve_internal(target, fragment):
        if not target:
            if fragment:
                fslug = str(current_file.relative_to(staging)).replace('/', '-').replace('.md', '')
                return ':ref:`{}-{}`'.format(fslug, slugify(fragment))
            return None
        try:
            resolved = (current_file.parent / target).resolve()
            rel = str(resolved.relative_to(staging))
        except (ValueError, OSError):
            return None
        for key in (rel, rel + '.md', rel.rstrip('/') + '/index.md'):
            if key in file_labels:
                return ':ref:`{}`'.format(file_labels[key])
        return None

    def register_image(img_url, alt, link_url=None):
        """Register an image substitution and return its |name|."""
        key = '{}:{}'.format(img_url, link_url or '')
        if key not in image_subs:
            name = image_sub_name(image_subs)
            image_subs[key] = (name, img_url, alt or 'image', link_url)
        return '|{}|'.format(image_subs[key][0])

    def replace_image_link(m):
        """Handle [![alt](img_url)](link_url) — clickable badge."""
        alt, img_url, link_url = m.group(1), m.group(2), m.group(3)
        return register_image(img_url, alt, link_url)

    def replace_link(m):
        link_text = m.group(1)
        raw = m.group(2).strip()
        if raw.startswith(('http://', 'https://', 'mailto:')):
            return '`{} <{}>`_'.format(link_text, raw.replace('`', r'\`'))
        target, fragment = (raw.split('#', 1) + [''])[:2]
        ref = resolve_internal(target, fragment)
        return ref if ref else link_text

    def replace_image(m):
        """Handle standalone ![alt](url)."""
        return register_image(m.group(2), m.group(1))

    # Split on inline code first to protect its content from substitution
    parts = re.split(r'(`[^`\n]+`)', text)
    out = []
    for tok in parts:
        if tok.startswith('`') and tok.endswith('`') and len(tok) > 1:
            out.append('``{}``'.format(tok[1:-1]))
            continue
        # Clickable badge images must be matched before the general link pattern
        tok = re.sub(r'\[!\[([^\]]*)\]\(([^)]+)\)\]\(([^)]+)\)', replace_image_link, tok)
        tok = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', replace_link, tok)
        tok = re.sub(r'!\[([^\]]*)\]\(([^)]+)\)', replace_image, tok)
        tok = re.sub(r'\*\*\*(.+?)\*\*\*', r'**\1**', tok)
        tok = re.sub(r'\*\*(.+?)\*\*',     r'**\1**', tok)
        tok = re.sub(r'\*(.+?)\*',          r'*\1*',   tok)
        out.append(tok)
    return ''.join(out)


_BLOCK_START = re.compile(
    r'^(#{1,6}\s|[-*+] |\d+\. |>|`{3,}|~{3,}|[-*_]{3,}\s*$)'
)


def convert_file(md_text, file_labels, staging, current_file, file_slug, image_subs):
    """Convert a single Markdown file to an RST fragment."""
    text = strip_frontmatter(md_text)
    lines = text.splitlines()
    out = []
    i = 0

    def il(t):
        return inline_rst(t, file_labels, staging, current_file, image_subs)

    while i < len(lines):
        line = lines[i]

        # ── Fenced code block (``` or ~~~) ──────────────────────────────────
        m = re.match(r'^(`{3,}|~{3,})(.*)', line)
        if m:
            fence, info = m.group(1), m.group(2).strip()
            i += 1
            if info.startswith('{'):    # MyST directive — skip silently
                while i < len(lines) and not lines[i].startswith(fence[:3]):
                    i += 1
                i += 1
                continue
            lang = info.split()[0] if info else ''
            code = []
            while i < len(lines) and not lines[i].startswith(fence[:3]):
                code.append('   ' + lines[i])
                i += 1
            i += 1
            directive = '.. code-block:: {}\n\n'.format(lang) if lang else '::\n\n'
            out.append(directive + '\n'.join(code))
            continue

        # ── ATX heading ─────────────────────────────────────────────────────
        m = re.match(r'^(#{1,6})\s+(.*)', line)
        if m:
            lvl = len(m.group(1))
            txt = m.group(2).rstrip('#').strip()
            label = '{}-{}'.format(file_slug, slugify(txt))
            out.append(rst_heading(txt, lvl, label=label))
            i += 1
            continue

        # ── Horizontal rule → RST transition ────────────────────────────────
        if re.match(r'^[-*_]{3,}\s*$', line):
            out.append('----')
            i += 1
            continue

        # ── GFM table ───────────────────────────────────────────────────────
        if '|' in line and i + 1 < len(lines) and re.match(r'^[\s|:\-]+$', lines[i + 1]):
            cols = [il(c.strip()) for c in line.strip('| ').split('|')]
            i += 2
            rows = []
            while i < len(lines) and '|' in lines[i]:
                row = [il(c.strip()) for c in lines[i].strip('| ').split('|')]
                while len(row) < len(cols):
                    row.append('')
                rows.append(row)
                i += 1
            tbl = [
                '.. list-table::',
                '   :header-rows: 1',
                '   :widths: auto',
                '',
                '   * - ' + '\n     - '.join(cols),
            ]
            for row in rows:
                tbl.append('   * - ' + '\n     - '.join(row))
            out.append('\n'.join(tbl))
            continue

        # ── Blockquote ───────────────────────────────────────────────────────
        if line.startswith('>'):
            bq = []
            while i < len(lines) and lines[i].startswith('>'):
                bq.append('   ' + lines[i][1:].lstrip(' '))
                i += 1
            out.append('\n'.join(bq))
            continue

        # ── Unordered list ───────────────────────────────────────────────────
        if re.match(r'^[-*+] ', line):
            items = []
            while i < len(lines) and re.match(r'^[-*+] ', lines[i]):
                items.append('- ' + il(lines[i][2:].strip()))
                i += 1
            out.append('\n'.join(items))
            continue

        # ── Ordered list ─────────────────────────────────────────────────────
        if re.match(r'^\d+\. ', line):
            items = []
            n = 1
            while i < len(lines) and re.match(r'^\d+\. ', lines[i]):
                items.append('{}. {}'.format(n, il(re.sub(r'^\d+\. ', '', lines[i]))))
                n += 1
                i += 1
            out.append('\n'.join(items))
            continue

        # ── Blank line ───────────────────────────────────────────────────────
        if not line.strip():
            out.append('')
            i += 1
            continue

        # ── Paragraph ────────────────────────────────────────────────────────
        para = []
        while i < len(lines) and lines[i].strip():
            if _BLOCK_START.match(lines[i]):
                break
            if '|' in lines[i] and i + 1 < len(lines) and re.match(r'^[\s|:\-]+$', lines[i + 1]):
                break
            para.append(lines[i])
            i += 1
        if para:
            out.append(il(' '.join(para)))

    return '\n\n'.join(s for s in out if s != '')


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 3:
        sys.exit('usage: {} <staging-dir> <output.rst> [version-str]'.format(sys.argv[0]))

    staging    = Path(sys.argv[1]).resolve()
    out_path   = Path(sys.argv[2])
    version    = sys.argv[3] if len(sys.argv) > 3 else 'unknown'

    # ── Step 1: collect content files in index-defined order ────────────────
    content_files = collect_ordered(staging)

    # ── Step 2: pass 1 — build {rel_path → RST label of first heading} ──────
    file_labels = {}
    for fpath in content_files:
        rel = str(fpath.relative_to(staging))
        fslug = rel.replace('/', '-').replace('.md', '')
        md = strip_frontmatter(fpath.read_text(encoding='utf-8'))
        for line in md.splitlines():
            m = re.match(r'^#{1,6}\s+(.*)', line)
            if m:
                heading = m.group(1).rstrip('#').strip()
                file_labels[rel] = '{}-{}'.format(fslug, slugify(heading))
                break

    # ── Step 3: extract intro paragraph from root index.md ──────────────────
    root_index = staging / 'index.md'
    intro = ''
    if root_index.is_file():
        raw = strip_frontmatter(root_index.read_text(encoding='utf-8'))
        para, past_title = [], False
        for line in raw.splitlines():
            if re.match(r'^#{1,6}\s', line):
                if past_title:
                    break
                past_title = True
                continue
            if not past_title:
                continue
            if line.strip() and re.match(r'^[-*+] |\d+\. |>', line):
                break
            if line.strip():
                para.append(line.strip())
            elif para:
                break
        intro = ' '.join(para).strip()

    # ── Step 4: image substitutions dict (populated during pass 2) ──────────
    image_subs = {}   # key → (name, img_url, alt, target_url_or_None)

    # ── Step 5: pass 2 — convert each file to RST ───────────────────────────
    converted = []
    for fpath in content_files:
        rel = str(fpath.relative_to(staging))
        fslug = rel.replace('/', '-').replace('.md', '')
        try:
            rst = convert_file(
                fpath.read_text(encoding='utf-8'),
                file_labels, staging, fpath, fslug, image_subs,
            )
            if rst.strip():
                converted.append(rst)
        except Exception as e:
            print('warning: skipping {}: {}'.format(fpath, e), file=sys.stderr)

    # ── Step 6: assemble the RST document ───────────────────────────────────
    doc_title = 'Pantavisor Reference Documentation'
    meta_block = (
        ':Version: ``{version}``\n'
        ':Pantavisor: `{pv_url} <{pv_url}>`_\n'
        ':meta-pantavisor: `{mpv_url} <{mpv_url}>`_'
    ).format(
        version=version,
        pv_url=PANTAVISOR_REPO,
        mpv_url=META_PANTAVISOR_REPO,
    )

    parts = []

    # Image substitution definitions come first so Sphinx can resolve them
    # anywhere in the document
    if image_subs:
        parts.append(render_image_subs(image_subs))

    parts += [
        rst_title(doc_title),
        '',
        intro or (
            'Complete reference documentation for the Pantavisor embedded Linux '
            'runtime and the meta-pantavisor Yocto/OpenEmbedded layer.'
        ),
        '',
        meta_block,
        '',
        '.. contents:: Table of Contents',
        '   :depth: 2',
        '',
        '----',
        '',
    ]

    parts.extend(converted)

    out_path.write_text('\n'.join(parts), encoding='utf-8')
    print('merged {} files → {}'.format(len(content_files), out_path))


if __name__ == '__main__':
    main()
