# Mermaid terminal preview

Place the cursor in a fenced `mermaid` block and press **Space c m**, or run
`:MermaidPreview`. Standalone `.mmd` and `.mermaid` files also work. The diagram
opens in a read-only floating window; press `q` or Escape to close it. Use normal
Neovim navigation (`j`/`k`, `zh`/`zl`) for diagrams larger than the window.

The `merman-nvim` helper is installed by the shared Home Manager Neovim module.
It uses OpenCode's Merman parser and grid layout, pinned to commit
`044d8b7d2e5dceef7adc6e620e53e70707b88951`. Node is supplied by the Nix wrapper;
no browser, image protocol, npm downloads at runtime, or sandbox override is used.
Supported types: flowchart, sequenceDiagram, stateDiagram, gantt, gitGraph,
timeline. Other types and unsupported Mermaid syntax report an error without
changing the source buffer. This is not a full replacement for Mermaid.js.

The helper returns Unicode lines and semantic style spans (UTF-8 byte offsets).
Neovim maps those styles to colorscheme highlights. Merman's OpenTUI UI adapter
is not used; `packages/merman/opentui.ts` supplies only the drawing constants.
Source is sent via stdin, not temporary files or interpolated shell commands.
Requests are asynchronous, limited to 128 KiB, and time out after ten seconds.

Snacks remains enabled for ordinary images. The plugin explicitly installs
`queries/markdown/images.scm` to omit Mermaid-to-PNG conversion while retaining
math blocks; ordinary Markdown image queries live in `markdown_inline`.

## Tests

```sh
nvim --clean --headless -l config/nvim/tests/merman.lua
```

Renderer tests run during the Nix package build. The Neovim tests require the
installed `merman-nvim` helper for their end-to-end cases.
