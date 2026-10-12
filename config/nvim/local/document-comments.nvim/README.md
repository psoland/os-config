# document-comments.nvim

A local, dependency-free Neovim 0.12 plugin for durable annotations anchored to
Markdown text: comments, delete requests, and looks-good feedback. Annotations are
stored per project in `.document-comments/comments.json`; open annotations can be exported to
`.document-comments/export.md` for agent work.

## Workflow

1. Save a Markdown file and select text characterwise or linewise.
2. Press `<leader>aa`, write the comment in the floating buffer, then use `:w`.
   Alternatively, `<leader>ad` adds a delete request and `<leader>ag` marks the
   selection looks good.
3. Use `<leader>as` for the persistent sidebar, or `<leader>al` for the existing
   comment list. Resolve or reopen annotations yourself with `<leader>ar`.
4. Use `<leader>ax` to export new/edited open annotations, then `/comments` in OpenCode
   to process the export. `<leader>aX` explicitly exports all open annotations again.
5. Use `<leader>av` to review changed or detached comments, then resolve them
   yourself.

The plugin never changes `.gitignore`. Decide whether each project's
`.document-comments` directory should remain local or be committed. Unwritten
comment drafts are not crash-recovered.

Open comments are marked in the sign column and counted in the statusline.
Single open delete requests use `−` with a delete highlight, and looks-good
annotations use `✓` with an add highlight. Resolved annotations use `○`.
`!` means an open comment is ambiguous, orphaned, or its selected text has
changed. Source edits never resolve a comment automatically: deletion alone is
not proof that the feedback was handled correctly.

## Keymaps

| Key | Mode | Action |
| --- | --- | --- |
| `<leader>aa` | Visual | Add comment |
| `<leader>ad` | Visual | Add delete request (does not edit the source) |
| `<leader>ag` | Visual | Add looks-good feedback |
| `<leader>as` | Normal | Toggle persistent annotation sidebar |
| `<leader>al` | Normal | List open comments in the current file |
| `<leader>aL` | Normal | List open comments in the project |
| `<leader>ae` | Normal | Edit comment under cursor |
| `<leader>ar` | Normal | Resolve or reopen |
| `<leader>av` | Normal | Review changed or detached comments |
| `<leader>an` / `<leader>ap` | Normal | Next / previous open comment |
| `<leader>aR` | Visual | Reattach an ambiguous or orphaned comment |
| `<leader>ax` | Normal | Export new/edited open project annotations |
| `<leader>aX` | Normal | Export all open project annotations |
| `<leader>ab` | Normal | Browse export batches |
| `<leader>ad` | Normal | Permanently delete an annotation after confirmation |

Edit, resolve, delete, and current-comment export first use a comment containing
the cursor, then comments on the same line. If neither exists, they offer the
comments in the current file instead of failing.

Selecting a comment in either list opens an action menu for jumping, editing,
resolving or reopening, deleting, and—when relevant—reattaching it. Delete still
requires confirmation. After edit, status change, or deletion, the refreshed
list opens again so several comments can be processed in one pass.

## Annotation types

Delete and looks-good annotations save immediately without opening an editor.
Use `<leader>ae` to add an optional note later. Ordinary comments still require a
nonempty body. The sidebar's `t` action or the list's **Change annotation type…**
action changes the type of an existing annotation. Converting an empty typed
annotation to an ordinary comment opens the editor first.

All three types use the same anchoring, references, and explicit resolution.
**Delete** requests removing selected source text; it never deletes text itself.
**Looks good** is positive feedback, not an instruction for the agent to rewrite
the selection or mark the annotation resolved.

`:DocumentCommentsAdd [comment|delete|looks_good]` also works from a Visual selection.

## Sidebar

The sidebar shows full comment bodies, selected text, type, and export coverage.
Selecting an attached annotation highlights its live range in the source window,
including through unsaved edits. It stays open and refreshes after changes.
It follows other Markdown files in the same project; project mode shows all files.
The header only shows the project, current scope/filter, counts, and a `? help`
hint. Press `?` for the shortcut guide in a read-only popup; `?`, `q`, or `Esc`
closes the popup and returns to the sidebar.

| Key | Sidebar action |
| --- | --- |
| `?` | Open shortcut help popup |
| `j` / `k` | Next / previous annotation (arrow keys move within long bodies) |
| `Enter` | Jump to source |
| `e` | Edit note |
| `r` | Resolve / reopen |
| `t` | Change annotation type |
| `a` | Choose this annotation for reattachment; select replacement source text, then `<leader>aR` |
| `d` | Permanently delete after confirmation |
| `y` | Copy stable ID |
| `]` / `[` | Open references / backlinks |
| `f` | Filter open, resolved, needs-review (`review`), new/edited (`new`), or all |
| `p` | Toggle file / project scope |
| `x` / `X` | Export new/edited / all open annotations in this scope |
| `B` | Browse export batches |
| `q` | Close sidebar |

Configure the width with `setup({ sidebar = { width = 48 } })` (minimum 20 columns).

## Incremental exports and batches

```vim
:DocumentCommentsExport
:DocumentCommentsExport new file
:DocumentCommentsExport all project
:DocumentCommentsExport all current
:DocumentCommentsExport new project /path/to/feedback.md
:DocumentCommentsBatches
```

The old `project`, `file`, and `current` scope syntax remains accepted, now with
incremental behavior by default. Each successful export records a batch in
`comments.json`: its ID, time, destination, scope, mode, pre-export store revision,
complete annotation snapshots, and the exact exported Markdown (including reference
context). Batch history is retained even after editing or permanently deleting an
annotation; it can be opened read-only with `<leader>ab` or sidebar `B`.

Export coverage survives restarts and is independent of destination or scope.
Changes to a note, type, selected text, source path, or anchor safety state make
an open annotation new/edited again. Merely moving the selection, updating nearby
context, or changing document hashes/timestamps does not. Unchanged reopened
annotations retain their export coverage; use an all-open export to send them again.

**Exported is not sent, addressed, or resolved.** Exports never change annotation
status. If there is nothing new, the previous export file is left untouched and no
batch is added. Failed exports do not advance coverage. If the export file was
written but recording its batch fails, the error says so and feedback remains
eligible for retry. History grows as batches are added; there is no automatic pruning.

Existing v1 stores load as ordinary comments and migrate to schema v2 on the next
successful store write. Invalid data and newer schemas still block writes. The
store remains project-local, with atomic writes and external-change detection.
Quoted Markdown uses adaptive backtick fences so embedded code blocks cannot
break out of the exported selection.

## References

Comment bodies can refer to stable project comment IDs:

```text
As discussed in @c_ab12f3, this should use the same terminology.
```

Typing `@` in the comment editor opens completion for project comments. Full
IDs are inserted, while manually written unambiguous prefixes such as
`@c_ab12` are also accepted. Unknown, ambiguous, and self-references produce a
warning but do not block saving.

The list action menu can copy an ID, open referenced comments, and show
backlinks. Deleting a referenced comment warns about the backlinks. Exports
include referenced comments recursively as context, including resolved
comments, and safely stop at circular references.

Run `:DocumentCommentsList all` to include resolved comments in the current
file, or `:DocumentCommentsListProject all` for the whole project.
`:DocumentCommentsStorePath` shows the active root and store. See command
completion for the `project`, `file`, and `current` export scopes.

## Tests

```sh
nvim --clean --headless \
  -u config/nvim/local/document-comments.nvim/tests/minimal_init.lua \
  -l config/nvim/local/document-comments.nvim/tests/run.lua
```
