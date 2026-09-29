-- Typst reads image paths itself, so Pandoc's --resource-path does not
-- resolve them for the PDF engine. Resolve Markdown images before writing Typst.
function Image(image)
  if image.src:match("^%a[%w+.-]*:") or image.src:sub(1, 1) == "/" then
    return nil
  end

  for _, root in ipairs({
    os.getenv("KNOWIT_PDF_INPUT_DIR"),
    os.getenv("KNOWIT_PDF_CALLER_DIR"),
    os.getenv("KNOWIT_PDF_ASSETS_DIR"),
  }) do
    local candidate = root .. "/" .. image.src
    local file = io.open(candidate, "rb")
    if file then
      file:close()
      image.src = candidate
      return image
    end
  end
end
