# document-comments.nvim

A local, dependency-free Neovim 0.12 plugin for durable comments anchored to
Markdown text. Comments are stored per project in
`.document-comments/comments.json`; open comments can be exported to
`.document-comments/export.md` for agent work.

## Workflow

1. Save a Markdown file and select text characterwise or linewise.
2. Press `<leader>aa`, write the comment in the floating buffer, then use `:w`.
3. Use `<leader>al` to list comments in the current file and `<leader>ar` to
   resolve or reopen one.
4. Use `<leader>ax` and then `/comments` in OpenCode to process the export.
5. Use `<leader>av` to review changed or detached comments, then resolve them
   yourself.

The plugin never changes `.gitignore`. Decide whether each project's
`.document-comments` directory should remain local or be committed. Unwritten
comment drafts are not crash-recovered.

Open comments are marked in the sign column and counted in the statusline.
`!` means an open comment is ambiguous, orphaned, or its selected text has
changed. Source edits never resolve a comment automatically: deletion alone is
not proof that the feedback was handled correctly.

## Keymaps

| Key | Mode | Action |
| --- | --- | --- |
| `<leader>aa` | Visual | Add comment |
| `<leader>al` | Normal | List open comments in the current file |
| `<leader>aL` | Normal | List open comments in the project |
| `<leader>ae` | Normal | Edit comment under cursor |
| `<leader>ar` | Normal | Resolve or reopen |
| `<leader>av` | Normal | Review changed or detached comments |
| `<leader>an` / `<leader>ap` | Normal | Next / previous open comment |
| `<leader>aR` | Visual | Reattach an ambiguous or orphaned comment |
| `<leader>ax` | Normal | Export open project comments |
| `<leader>ad` | Normal | Delete after confirmation |

Edit, resolve, delete, and current-comment export first use a comment containing
the cursor, then comments on the same line. If neither exists, they offer the
comments in the current file instead of failing.

Selecting a comment in either list opens an action menu for jumping, editing,
resolving or reopening, deleting, and—when relevant—reattaching it. Delete still
requires confirmation. After edit, status change, or deletion, the refreshed
list opens again so several comments can be processed in one pass.

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
