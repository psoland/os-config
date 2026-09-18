# document-comments.nvim

A local, dependency-free Neovim 0.12 plugin for durable comments anchored to
Markdown text. Comments are stored per project in
`.document-comments/comments.json`; open comments can be exported to
`.document-comments/export.md` for agent work.

## Workflow

1. Save a Markdown file and select text characterwise or linewise.
2. Press `<leader>aa`, write the comment in the floating buffer, then use `:w`.
3. Use `<leader>al` to list comments and `<leader>ar` to resolve or reopen one.
4. Use `<leader>ax` and then `/comments` in OpenCode to process the export.
5. Review source changes and resolve comments yourself.

The plugin never changes `.gitignore`. Decide whether each project's
`.document-comments` directory should remain local or be committed. Unwritten
comment drafts are not crash-recovered.

## Keymaps

| Key | Mode | Action |
| --- | --- | --- |
| `<leader>aa` | Visual | Add comment |
| `<leader>al` | Normal | List open comments |
| `<leader>ae` | Normal | Edit comment under cursor |
| `<leader>ar` | Normal | Resolve or reopen |
| `<leader>an` / `<leader>ap` | Normal | Next / previous open comment |
| `<leader>aR` | Visual | Reattach an ambiguous or orphaned comment |
| `<leader>ax` | Normal | Export open project comments |
| `<leader>ad` | Normal | Delete after confirmation |

Run `:DocumentCommentsList all` to include resolved comments and
`:DocumentCommentsStorePath` to inspect the active root and store. See command
completion for the `project`, `file`, and `current` export scopes.

## Tests

```sh
nvim --clean --headless \
  -u config/nvim/local/document-comments.nvim/tests/minimal_init.lua \
  -l config/nvim/local/document-comments.nvim/tests/run.lua
```
