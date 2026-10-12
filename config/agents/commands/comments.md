---
description: Apply exported document comments to their Markdown sources
---

# Apply document comments

Read the document-comment export at `$ARGUMENTS`, or
`.document-comments/export.md` when no path was supplied.

For every annotation ID in a top-level section of the export:

1. Read the referenced Markdown source file and the exported quote and context.
2. Follow its type: `comment` requests a change or clarification; `delete` requests
   removing the selected text; `looks_good` is positive feedback and requires no edit.
   Older exports without a type are ordinary comments. Make any needed edits only
   in the referenced source document.
3. Do not edit `.document-comments/comments.json`, the export file, or any
   comment status.
4. Do not guess when an `ambiguous` or `orphaned` anchor does not identify a
   safe edit; report the blocker instead.
5. Summarize the change, acknowledgement, or blocker separately for each annotation
   ID when finished. Exported does not mean sent or resolved; only the user resolves feedback.

Referenced-comment sections are context only, not additional tasks unless the
comment also has its own top-level section.
