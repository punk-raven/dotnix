-- ============================================================================
-- Vim options (adopted from raveracker/dotfiles: lua/vim_config.lua)
-- Leader MUST be set before any <leader> mapping is defined below.
-- ============================================================================
local o = vim.opt
vim.g.mapleader   = " "           -- space is the leader key
o.expandtab       = true          -- spaces, not tabs
o.shiftwidth      = 2             -- 2 spaces per indent level
o.number          = true
o.relativenumber  = true          -- relative line numbers for fast jumps
o.ignorecase      = true
o.smartcase       = true          -- case-sensitive only if you type a capital
o.clipboard       = "unnamedplus" -- share the system clipboard
o.scrolloff       = 16            -- keep cursor away from the screen edge
o.undofile        = true          -- persistent undo across sessions

-- ============================================================================
-- plenary.nvim - Lua library; HARD dependency of neogit and diffview.
-- Added first so those plugins can require it. (vim.pack does no dep resolution)
-- ============================================================================
vim.pack.add({ "https://github.com/nvim-lua/plenary.nvim" })

-- 1. mini.icons - icon provider shared by oil, snacks, neogit. (existing)
vim.pack.add({ "https://github.com/nvim-mini/mini.icons" })
require("mini.icons").setup()
MiniIcons.mock_nvim_web_devicons()

-- 2. snacks.nvim - QoL collection. (existing, unchanged)
vim.pack.add({ "https://github.com/folke/snacks.nvim" })
require("snacks").setup({
  bigfile   = { enabled = true },
  quickfile = { enabled = true },
  picker    = { enabled = true },
  notifier  = { enabled = true },
  indent    = { enabled = true },
  scope     = { enabled = true },
  input     = { enabled = true },
})
vim.keymap.set("n", "<leader>ff", function() Snacks.picker.files() end, { desc = "Find files" })
vim.keymap.set("n", "<leader>fg", function() Snacks.picker.grep() end,  { desc = "Grep" })
vim.keymap.set("n", "<leader>fb", function() Snacks.picker.buffers() end, { desc = "Buffers" })
vim.keymap.set("n", "<leader>e",  function() Snacks.explorer() end,     { desc = "File explorer" })
vim.keymap.set("n", "gd", function() Snacks.picker.lsp_definitions() end, { desc = "Goto definition" })

-- 3. oil.nvim - edit the filesystem like a buffer. (existing, unchanged)
vim.pack.add({ "https://github.com/stevearc/oil.nvim" })
require("oil").setup({ view_options = { show_hidden = true } })
vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })

-- 4. neogit - Magit-style git interface. (existing; now actually works via plenary)
vim.pack.add({ "https://github.com/NeogitOrg/neogit" })
require("neogit").setup({})
vim.keymap.set("n", "<leader>gg", "<cmd>Neogit<cr>", { desc = "Open Neogit" })

-- 5. diffview.nvim - side-by-side git diff / file history. (NEW, from raveracker)
vim.pack.add({ "https://github.com/sindrets/diffview.nvim" })
require("diffview").setup()
vim.keymap.set("n", "<leader>gd", "<cmd>DiffviewOpen<cr>",        { desc = "Diffview: open" })
vim.keymap.set("n", "<leader>gh", "<cmd>DiffviewFileHistory<cr>", { desc = "Diffview: file history" })

-- 6. gitsigns.nvim - git gutter signs + current-line blame. (NEW, from raveracker)
vim.pack.add({ "https://github.com/lewis6991/gitsigns.nvim" })
require("gitsigns").setup({ current_line_blame = true })

-- 7. which-key.nvim - popup of available <leader> mappings. (NEW, from raveracker)
vim.pack.add({ "https://github.com/folke/which-key.nvim" })
require("which-key").setup({})

-- ============================================================================
-- Keymaps (adopted from raveracker/dotfiles: lua/keys.lua)
-- ============================================================================
vim.keymap.set("n", "<Esc>", ":w<CR>", { desc = "Save" })
vim.keymap.set("n", "<C-a>", "ggVG",   { desc = "Select all" })
vim.cmd([[ xnoremap <expr> p 'pgv"'.v:register.'y' ]])
