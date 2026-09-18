---
description: Apply exported document comments to their Markdown sources
---

# Apply document comments

Read the document-comment export at `$ARGUMENTS`, or
`.document-comments/export.md` when no path was supplied.

For every comment ID in the export:

1. Read the referenced Markdown source file and the exported quote and context.
2. Address the comment by editing only the referenced source document.
3. Do not edit `.document-comments/comments.json`, the export file, or any
   comment status.
4. Do not guess when an `ambiguous` or `orphaned` anchor does not identify a
   safe edit; report the blocker instead.
5. Summarize the change or blocker separately for each comment ID when finished.
