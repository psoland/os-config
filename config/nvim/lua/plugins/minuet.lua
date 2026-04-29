if vim.env.NVIM_ENABLE_MINUET ~= "1" then
  return {}
end

return {
  {
    "milanglacier/minuet-ai.nvim",
    dependencies = {
      "Saghen/blink.cmp",
    },
    opts = {
      provider = "openai_fim_compatible",
      n_completions = 1,
      context_window = 512,
      provider_options = {
        openai_fim_compatible = {
          api_key = "TERM",
          name = "Llama.cpp",
          end_point = "http://127.0.0.1:8012/v1/completions",
          model = "PLACEHOLDER",
          optional = {
            max_tokens = 64,
            top_p = 0.9,
          },
          template = {
            prompt = function(context_before_cursor, context_after_cursor, _)
              return "<|fim_prefix|>" .. context_before_cursor .. "<|fim_suffix|>" .. context_after_cursor .. "<|fim_middle|>"
            end,
            suffix = false,
          },
        },
      },
      blink = {
        enable_auto_complete = true,
      },
    },
  },
  {
    "Saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.default = opts.sources.default or {}
      if not vim.tbl_contains(opts.sources.default, "minuet") then
        table.insert(opts.sources.default, "minuet")
      end
    end,
  },
}
