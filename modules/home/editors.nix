# Neovim configuration
{ config, pkgs, lib, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;

    # Use latest neovim
    package = pkgs.neovim-unwrapped;

    # Aliases
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    # Support for languages
    withNodeJs = true;
    withPython3 = true;

    # Extra packages available to neovim
    extraPackages = with pkgs; [
      # LSP servers
      lua-language-server
      nil  # Nix LSP
      nodePackages.typescript-language-server
      nodePackages.vscode-langservers-extracted  # HTML, CSS, JSON, ESLint
      pyright
      gopls
      rust-analyzer

      # Formatters
      nixpkgs-fmt
      prettierd
      stylua
      black
      isort
      gofumpt

      # Linters
      shellcheck
      hadolint

      # Tools
      tree-sitter
      gcc  # For treesitter compilation
      gnumake
    ];

    # Extra Lua configuration
    extraLuaConfig = ''
      -- Leader key
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "

      -- Basic settings
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.mouse = "a"
      vim.opt.showmode = false
      vim.opt.clipboard = "unnamedplus"
      vim.opt.breakindent = true
      vim.opt.undofile = true
      vim.opt.ignorecase = true
      vim.opt.smartcase = true
      vim.opt.signcolumn = "yes"
      vim.opt.updatetime = 250
      vim.opt.timeoutlen = 300
      vim.opt.splitright = true
      vim.opt.splitbelow = true
      vim.opt.list = true
      vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
      vim.opt.inccommand = "split"
      vim.opt.cursorline = true
      vim.opt.scrolloff = 10
      vim.opt.hlsearch = true

      -- Indentation
      vim.opt.tabstop = 2
      vim.opt.shiftwidth = 2
      vim.opt.softtabstop = 2
      vim.opt.expandtab = true
      vim.opt.smartindent = true

      -- Appearance
      vim.opt.termguicolors = true
      vim.opt.background = "dark"

      -- Basic keymaps
      vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
      vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostic [Q]uickfix list" })
      vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

      -- Window navigation
      vim.keymap.set("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus to the left window" })
      vim.keymap.set("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus to the right window" })
      vim.keymap.set("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus to the lower window" })
      vim.keymap.set("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus to the upper window" })

      -- Buffer navigation
      vim.keymap.set("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
      vim.keymap.set("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })

      -- Better indenting
      vim.keymap.set("v", "<", "<gv")
      vim.keymap.set("v", ">", ">gv")

      -- Move lines
      vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
      vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

      -- Save file
      vim.keymap.set({ "n", "i", "v", "s" }, "<C-s>", "<cmd>w<CR><Esc>", { desc = "Save file" })

      -- Highlight on yank
      vim.api.nvim_create_autocmd("TextYankPost", {
        desc = "Highlight when yanking text",
        group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
        callback = function()
          vim.highlight.on_yank()
        end,
      })
    '';

    # Plugins
    plugins = with pkgs.vimPlugins; [
      # Theme
      {
        plugin = catppuccin-nvim;
        type = "lua";
        config = ''
          require("catppuccin").setup({
            flavour = "mocha",
            transparent_background = false,
            integrations = {
              cmp = true,
              gitsigns = true,
              nvimtree = true,
              treesitter = true,
              telescope = { enabled = true },
              mini = { enabled = true },
            },
          })
          vim.cmd.colorscheme "catppuccin"
        '';
      }

      # File explorer
      {
        plugin = oil-nvim;
        type = "lua";
        config = ''
          require("oil").setup({
            default_file_explorer = true,
            columns = { "icon" },
            keymaps = {
              ["g?"] = "actions.show_help",
              ["<CR>"] = "actions.select",
              ["<C-v>"] = "actions.select_vsplit",
              ["<C-s>"] = "actions.select_split",
              ["<C-p>"] = "actions.preview",
              ["<C-c>"] = "actions.close",
              ["-"] = "actions.parent",
              ["_"] = "actions.open_cwd",
            },
            view_options = { show_hidden = true },
          })
          vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })
        '';
      }

      # Icons
      nvim-web-devicons

      # Fuzzy finder
      plenary-nvim
      {
        plugin = telescope-nvim;
        type = "lua";
        config = ''
          require("telescope").setup({
            defaults = {
              mappings = {
                i = {
                  ["<C-j>"] = require("telescope.actions").move_selection_next,
                  ["<C-k>"] = require("telescope.actions").move_selection_previous,
                },
              },
            },
          })
          local builtin = require("telescope.builtin")
          vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "[F]ind [F]iles" })
          vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "[F]ind by [G]rep" })
          vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "[F]ind [B]uffers" })
          vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "[F]ind [H]elp" })
          vim.keymap.set("n", "<leader>fr", builtin.oldfiles, { desc = "[F]ind [R]ecent" })
          vim.keymap.set("n", "<leader><leader>", builtin.buffers, { desc = "Find existing buffers" })
        '';
      }
      telescope-fzf-native-nvim

      # Treesitter
      {
        plugin = nvim-treesitter.withAllGrammars;
        type = "lua";
        config = ''
          require("nvim-treesitter.configs").setup({
            highlight = { enable = true },
            indent = { enable = true },
            incremental_selection = {
              enable = true,
              keymaps = {
                init_selection = "<C-space>",
                node_incremental = "<C-space>",
                scope_incremental = false,
                node_decremental = "<bs>",
              },
            },
          })
        '';
      }

      # LSP
      {
        plugin = nvim-lspconfig;
        type = "lua";
        config = ''
          local lspconfig = require("lspconfig")
          local capabilities = vim.lsp.protocol.make_client_capabilities()

          -- Keymaps for LSP
          vim.api.nvim_create_autocmd("LspAttach", {
            group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
            callback = function(event)
              local map = function(keys, func, desc)
                vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
              end
              map("gd", vim.lsp.buf.definition, "[G]oto [D]efinition")
              map("gr", vim.lsp.buf.references, "[G]oto [R]eferences")
              map("gI", vim.lsp.buf.implementation, "[G]oto [I]mplementation")
              map("K", vim.lsp.buf.hover, "Hover Documentation")
              map("<leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")
              map("<leader>rn", vim.lsp.buf.rename, "[R]e[n]ame")
              map("<leader>D", vim.lsp.buf.type_definition, "Type [D]efinition")
            end,
          })

          -- Setup LSP servers
          lspconfig.lua_ls.setup({ capabilities = capabilities })
          lspconfig.nil_ls.setup({ capabilities = capabilities })
          lspconfig.ts_ls.setup({ capabilities = capabilities })
          lspconfig.pyright.setup({ capabilities = capabilities })
          lspconfig.gopls.setup({ capabilities = capabilities })
          lspconfig.rust_analyzer.setup({ capabilities = capabilities })
        '';
      }

      # Autocompletion
      {
        plugin = nvim-cmp;
        type = "lua";
        config = ''
          local cmp = require("cmp")
          cmp.setup({
            snippet = {
              expand = function(args)
                vim.snippet.expand(args.body)
              end,
            },
            completion = { completeopt = "menu,menuone,noinsert" },
            mapping = cmp.mapping.preset.insert({
              ["<C-n>"] = cmp.mapping.select_next_item(),
              ["<C-p>"] = cmp.mapping.select_prev_item(),
              ["<C-b>"] = cmp.mapping.scroll_docs(-4),
              ["<C-f>"] = cmp.mapping.scroll_docs(4),
              ["<C-y>"] = cmp.mapping.confirm({ select = true }),
              ["<C-Space>"] = cmp.mapping.complete(),
            }),
            sources = {
              { name = "nvim_lsp" },
              { name = "path" },
              { name = "buffer" },
            },
          })
        '';
      }
      cmp-nvim-lsp
      cmp-buffer
      cmp-path

      # Git
      {
        plugin = gitsigns-nvim;
        type = "lua";
        config = ''
          require("gitsigns").setup({
            signs = {
              add = { text = "+" },
              change = { text = "~" },
              delete = { text = "_" },
              topdelete = { text = "‾" },
              changedelete = { text = "~" },
            },
            on_attach = function(bufnr)
              local gs = package.loaded.gitsigns
              local function map(mode, l, r, opts)
                opts = opts or {}
                opts.buffer = bufnr
                vim.keymap.set(mode, l, r, opts)
              end
              map("n", "]c", gs.next_hunk, { desc = "Next hunk" })
              map("n", "[c", gs.prev_hunk, { desc = "Previous hunk" })
              map("n", "<leader>hs", gs.stage_hunk, { desc = "[H]unk [S]tage" })
              map("n", "<leader>hr", gs.reset_hunk, { desc = "[H]unk [R]eset" })
              map("n", "<leader>hp", gs.preview_hunk, { desc = "[H]unk [P]review" })
              map("n", "<leader>hb", function() gs.blame_line({ full = true }) end, { desc = "[H]unk [B]lame" })
            end,
          })
        '';
      }

      # Status line
      {
        plugin = lualine-nvim;
        type = "lua";
        config = ''
          require("lualine").setup({
            options = {
              theme = "catppuccin",
              component_separators = { left = "|", right = "|" },
              section_separators = { left = "", right = "" },
            },
            sections = {
              lualine_a = { "mode" },
              lualine_b = { "branch", "diff", "diagnostics" },
              lualine_c = { { "filename", path = 1 } },
              lualine_x = { "encoding", "fileformat", "filetype" },
              lualine_y = { "progress" },
              lualine_z = { "location" },
            },
          })
        '';
      }

      # Autopairs
      {
        plugin = nvim-autopairs;
        type = "lua";
        config = ''
          require("nvim-autopairs").setup({})
        '';
      }

      # Comment toggling
      {
        plugin = comment-nvim;
        type = "lua";
        config = ''
          require("Comment").setup()
        '';
      }

      # Surround
      {
        plugin = nvim-surround;
        type = "lua";
        config = ''
          require("nvim-surround").setup({})
        '';
      }

      # Which-key for keybinding help
      {
        plugin = which-key-nvim;
        type = "lua";
        config = ''
          require("which-key").setup({})
          require("which-key").add({
            { "<leader>f", group = "[F]ind" },
            { "<leader>c", group = "[C]ode" },
            { "<leader>h", group = "[H]unk/Git" },
            { "<leader>r", group = "[R]ename" },
          })
        '';
      }

      # Indent guides
      {
        plugin = indent-blankline-nvim;
        type = "lua";
        config = ''
          require("ibl").setup({
            indent = { char = "│" },
            scope = { enabled = true },
          })
        '';
      }

      # Todo comments
      {
        plugin = todo-comments-nvim;
        type = "lua";
        config = ''
          require("todo-comments").setup({})
        '';
      }

      # Mini.nvim modules
      {
        plugin = mini-nvim;
        type = "lua";
        config = ''
          -- Better around/inside textobjects
          require("mini.ai").setup({ n_lines = 500 })
          -- Add/delete/replace surroundings (brackets, quotes, etc.)
          -- require("mini.surround").setup()  -- Using nvim-surround instead
        '';
      }
    ];
  };
}
