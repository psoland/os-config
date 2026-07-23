local load_fim = loadfile(vim.fn.stdpath("config") .. "-fim.lua")
if not load_fim then
  return {}
end

local fim = load_fim()

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
          -- Minuet requires a token even though local llama.cpp ignores it.
          api_key = function()
            return "local"
          end,
          name = "Llama.cpp",
          end_point = fim.endpoint,
          model = "PLACEHOLDER",
          optional = {
            max_tokens = 64,
            top_p = 0.9,
          },
          template = {
            prompt = function(context_before_cursor, context_after_cursor, _)
              return "<|fim_prefix|>"
                .. context_before_cursor
                .. "<|fim_suffix|>"
                .. context_after_cursor
                .. "<|fim_middle|>"
            end,
            suffix = false,
          },
        },
      },
      blink = {
        enable_auto_complete = false,
      },
    },
  },
  {
    "Saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      opts.keymap = opts.keymap or {}
      if opts.keymap["<C-y>"] == nil then
        opts.keymap["<C-y>"] = require("minuet").make_blink_map()
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
