; Override Snacks' Markdown image query: Mermaid is previewed by Merman,
; not converted through Chromium. Ordinary images use markdown_inline/images.
(fenced_code_block
  (info_string (language) @lang)
  (#eq? @lang "math")
  (code_fence_content) @image.content
  (#set! injection.language "latex")
  (#set! image.ext "math.tex")
) @image
