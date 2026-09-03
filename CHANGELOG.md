# Changelog

## 0.6.0 — 2026-09-03

Skip folders inside the searched ones (Settings, or `askmac skip add`). When Spotlight indexing is off for a volume, the app says so instead of finding nothing silently. When hundreds of files match, the ones whose names carry the words come first. Answers come in the language of the question. When the model says the files do not answer, the list is labelled "Closest matches".

## 0.5.0 — 2026-09-03

Files read during a session are kept in memory (capped) so follow-ups skip the reading phase; a changed file is read again. Follow-ups hand the model the earlier question and answer so "it" resolves. Mail is searched by default whenever it is readable, not only when a question says "email". Light stemming, so "invoices" finds "invoice" and "paying" finds "pay".

## 0.4.0 — 2026-09-03

PDF sources say which page. Quick Look on any source (the eye button). ⌘1 to ⌘9 open a source, ⇧⌘C copies the answer with its sources, ⌘. stops a question. Apple's model is raced against a 40-second clock and the answer falls back to a quoted sentence if it loses, so nothing can hang the window.

## 0.3.0 — 2026-09-03

Follow-up questions carry the previous question's words, dates and scope ("and when is rent due"), and a short question that finds nothing is retried as a follow-up. Excel and PowerPoint files are read. Mail sources show their subject instead of a file number. Very long PDFs stop after 120 pages. The status line says when Mail is left out for lack of Full Disk Access, with the pane one click away. Escape clears the question.

## 0.2.0 — 2026-09-03

The window says what it is doing and the answer streams in as it is written. Screenshots and photos are read with on-device text recognition when a question asks for them. Apple Notes are read through the Notes app when a question mentions notes. ⌥ Space brings the window forward.

## 0.1.0 — 2026-09-03

First build. Spotlight-backed retrieval over Documents, Desktop, Downloads, iCloud Drive and Mail; readers for PDF, Word, RTF, HTML, text, Markdown, CSV and .emlx; passage ranking by keywords and on-device word embeddings; answers written by Apple's on-device model on macOS 26 with citations, or quoted from the top file elsewhere; a command line with JSON.
