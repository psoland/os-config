return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      require("config.snacks-diagnostics").setup()
      return vim.tbl_deep_extend("force", opts, {
        scroll = { enabled = false },
        image = { enabled = true },
        lazygit = {
          config = {
            os = {
              edit = [=[[ -z "$NVIM" ] && nvim -- {{filename}} || (nvim --server "$NVIM" --remote-send "q" && nvim --server "$NVIM" --remote {{filename}})]=],
              editAtLine = [=[[ -z "$NVIM" ] && nvim +{{line}} -- {{filename}} || (nvim --server "$NVIM" --remote-send "q" && nvim --server "$NVIM" --remote {{filename}} && nvim --server "$NVIM" --remote-send ":{{line}}<CR>")]=],
              openDirInEditor = [=[[ -z "$NVIM" ] && nvim -- {{dir}} || (nvim --server "$NVIM" --remote-send "q" && nvim --server "$NVIM" --remote {{dir}})]=],
            },
          },
        },
        picker = {
          sources = {
            explorer = {
              hidden = true,
              ignored = true,
            },
            files = {
              hidden = true,
              ignored = true,
              -- Keep generated/dependency files out of <Space><Space>.
              exclude = {
                "node_modules",
                ".devenv",
                ".next",
                "build",
                "coverage",
                "dist",
              },
            },
          },
        },
      })
    end,
    keys = {
      {
        "<leader><space>",
        LazyVim.pick("files", { root = false }),
        desc = "Find Files (cwd)",
      },
      {
        "<leader>e",
        function()
          Snacks.explorer()
        end,
        desc = "Explorer Snacks (cwd)",
      },
      {
        "<leader>E",
        function()
          Snacks.explorer({ cwd = LazyVim.root() })
        end,
        desc = "Explorer Snacks (root dir)",
      },
    },
  },
}
