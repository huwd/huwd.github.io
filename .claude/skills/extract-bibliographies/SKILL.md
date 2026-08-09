---
name: extract-bibliographies
description: Finds books read in a given year that have an epub in the bookstore library, then extracts the text of any bibliography/notes/references back matter for citation-network analysis. Use when asked to pull bibliographies, extract references/notes/citations from books read this year (or a given year), or to build/refresh the raw data behind a book citation-network project.
---

# Extract Bibliographies

Wraps `scripts/extract_bibliographies.rb` — a deterministic, non-AI script
that matches `_books/*.md` against the bookstore OPDS catalog, downloads any
epub not already cached, and extracts back-matter sections (bibliography,
notes, references, further reading, etc.) by parsing each epub's table of
contents. The script never needs an LLM — your job is to run it, then act as
the sense-check on its output: catching back-matter sections it missed
because of unfamiliar phrasing, and reviewing new epub structures it can't
yet parse.

Must be run from the `huwdiprose.co.uk` project root. Requires `BOOKSTORE_HOST`,
`BOOKSTORE_USER`, `BOOKSTORE_PASSWORD` in `.env` (same credentials the
`book-verifier` agent uses).

## Step 1 — Run the script

```bash
bundle exec ruby scripts/extract_bibliographies.rb --year 2026
```

Defaults to the current year if `--year` is omitted. For testing a single
book without re-running the whole batch:

```bash
bundle exec ruby scripts/extract_bibliographies.rb --year 2026 --only "Against Money"
```

Output:

- `.tmp/bibliographies/epubs/<title>.epub` — cached download (skipped on
  re-run if already present; delete the file to force a re-download)
- `.tmp/bibliographies/extracted/<title>.json` — matched sections with raw
  text, per book
- `.tmp/bibliographies/report.json` — one row per book: `extracted`,
  `no_back_matter`, `not_in_library`, or `error`

All of `.tmp/` is gitignored — nothing here gets committed as a side effect.

## Step 2 — Sense-check `no_back_matter` books

This is the step the script can't do itself. For every book reported as
`no_back_matter` in `report.json`, read its `toc_tail` field (the last ~40
table-of-contents labels) and judge, book by book, whether any label is
plausibly a bibliography-style section that `BACK_MATTER_KEYWORDS` (in
`scripts/support/epub_toc.rb`) just doesn't recognize yet. Signs worth
extending the keyword list for:

- Idiosyncratic phrasing: "A Note on Sources", "Chapter Notes", "Suggested
  Reading", "Sources and Acknowledgments"
- Translated or regional variants
- A publisher-specific heading style seen across multiple books

Signs it's a genuine non-match, not a missed keyword — leave it alone:

- The book is fiction/narrative with only "Acknowledgements" or an "Index of
  Characters" (character indexes and thank-yous aren't citations)
- The `toc_tail` has no back-matter-shaped heading at all

If you find a real miss:

1. Add the new phrase to `BACK_MATTER_KEYWORDS` in
   `scripts/support/epub_toc.rb` — keep entries lowercase, matching the
   existing style.
2. Re-run just that book with `--only "<title>"` to confirm it now matches
   and the extracted text looks like an actual bibliography (not, say, an
   index or acknowledgements section that happened to share wording).
3. Only keep the keyword if it doesn't cause false positives — if unsure,
   ask the user before widening a keyword that could over-match on a future
   book's ordinary prose (e.g. a bare word like "sources" is already
   borderline; anything broader needs real justification).

Never edit `BACK_MATTER_KEYWORDS` to force a match on a book that genuinely
has no back matter — that defeats the point of the sense-check.

## Step 3 — Review `error` books

An `error` status means the epub itself couldn't be parsed (e.g. an
unrecognized OPF/TOC structure). Read the error message, inspect the raw
epub with `ruby -rzip -e '...'` (see `scripts/support/epub_toc.rb` for the
parsing approach — namespace-prefixed OPF tags like `<opf:item>` are one
known variant already handled), and fix `epub_toc.rb` if the structure is a
legitimate, previously-unhandled EPUB variant. Don't work around a parsing
bug by hand-extracting one book's data — fix the parser so the next run
(and every future book with the same structure) benefits.

## Step 4 — Playback

Summarize for the user in one place:

- Books extracted, with which sections were found per book
- Books with no back matter (expected — mostly fiction)
- Books not in the library (acquisition gaps — mention if any look worth
  filling via the shelfmark pipeline)
- Any `BACK_MATTER_KEYWORDS` additions made this run, and which book(s)
  prompted them

## Notes

- `BookMatcher` (in `scripts/support/bookstore_client.rb`) disambiguates by
  author only when a title match is ambiguous, and only requires _any_
  author overlap — translated works often have the catalog credit the
  translator as primary author, and multi-author books aren't always listed
  in the same order locally as in the catalog.
- The script falls back to an OPDS search when a book isn't found in the
  paginated catalog browse — bookstore's browse pagination and its search
  index have been observed out of sync for the same book.
- Section-extraction boundaries are exact when a TOC entry has its own
  content file, or when consecutive same-file entries have unambiguous
  anchor positions. `exact: false` in the extracted JSON means it fell back
  to dumping the whole file — check those by hand before trusting the text.
