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
      opts.keymap = opts.keymap or {}
      if opts.keymap["<A-y>"] == nil then
        opts.keymap["<A-y>"] = require("minuet").make_blink_map()
      end

      opts.sources = opts.sources or {}
      opts.sources.default = opts.sources.default or {}
      if not vim.tbl_contains(opts.sources.default, "minuet") then
        table.insert(opts.sources.default, "minuet")
      end

      opts.sources.providers = opts.sources.providers or {}
      opts.sources.providers.minuet = vim.tbl_deep_extend("force", opts.sources.providers.minuet or {}, {
        name = "minuet",
        module = "minuet.blink",
        async = true,
        timeout_ms = 3000,
        score_offset = 50,
      })

      opts.completion = opts.completion or {}
      opts.completion.trigger = opts.completion.trigger or {}
      opts.completion.trigger.prefetch_on_insert = false
    end,
  },
}
