return {
  {
    "folke/snacks.nvim",
    opts = {
      scroll = { enabled = false },
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
          },
        },
      },
    },
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
