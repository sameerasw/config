-- Bootstrap lazy.nvim if not installed
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim",
    lazypath
  })
end
vim.opt.rtp:prepend(lazypath)

-- Plugin setup
require("lazy").setup({
  { "tpope/vim-sensible" },
  { "shaunsingh/nord.nvim" },
  { "nvim-tree/nvim-web-devicons" },
  { "akinsho/bufferline.nvim", version = "*" },
  { "nvim-tree/nvim-tree.lua" },
  {'akinsho/bufferline.nvim', version = "*", dependencies = 'nvim-tree/nvim-web-devicons'},
  {
    "folke/which-key.nvim",
    config = function()
        require("which-key").setup()
    end,
  },
  {
  "folke/zen-mode.nvim",
    opts = {
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
    }
  },
  {
    "prettier/vim-prettier",
    run = "npm install",
    ft = { "javascript", "typescript", "css", "scss", "html", "json", "markdown", "yaml", "graphql", "vue", "svelte" },
  },






  -- Add dashboard-nvim plugin
  {
    'nvimdev/dashboard-nvim',
    event = 'VimEnter',
    config = function()
      require('dashboard').setup {
        -- You can put your dashboard configuration here, e.g.
        -- header = { "Welcome to Neovim!" },
        -- center = {
        --   { desc = 'Find File', action = 'Telescope find_files' },
        --   { desc = 'Recent Files', action = 'Telescope oldfiles' }
        -- }
      }
    end,
    dependencies = { {'nvim-tree/nvim-web-devicons'} }
  }

    })

-- General settings
vim.opt.termguicolors = tru

-- Nord theme and options
vim.cmd.colorscheme("nord")
vim.g.nord_disable_background = true

vim.g.nord_italic = true
vim.g.nord_uniform_diff_background = true
vim.g.nord_bold = true

-- Load the colorscheme
require('nord').set()

-- Disable netrw
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- nvim-tree config
require("nvim-tree").setup({
  sort = {
    sorter = "case_sensitive",
  },
  view = {
    width = 30,
  },
  renderer = {
    group_empty = true,
  },
  filters = {
    dotfiles = true,
  },
})

-- Open nvim-tree on startup and keep focus in editor
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    require("nvim-tree.api").tree.open()
    vim.cmd("wincmd l")
  end,
})

-- Auto-close Neovim when nvim-tree is the last window
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function()
    if #vim.api.nvim_list_wins() == 1 and vim.fn.bufname() == "NvimTree_" .. vim.fn.tabpagenr() then
      vim.cmd("quit")
    end
  end,
})

vim.opt.termguicolors = true
require("bufferline").setup{}


-- Auto format with Prettier on save
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.js", "*.ts", "*.jsx", "*.tsx", "*.json", "*.html", "*.css", "*.scss", "*.md", "*.yaml", "*.graphql", "*.vue", "*.svelte" },
  callback = function()
    vim.cmd("Prettier")
  end,
})

-- Auto format with Prettier after pasting
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    if vim.v.event.operator == "p" or vim.v.event.operator == "P" then
      vim.cmd("Prettier")
    end
  end,
})

vim.g["prettier#exec_cmd_path"] = "prettier"


------------------------------------
-- Enable line numbers
vim.opt.number = true       -- Show absolute line numbers
vim.opt.relativenumber = true  -- Show relative line numbers

-- Set tab size
vim.opt.tabstop = 4         -- Number of spaces a tab character will occupy
vim.opt.shiftwidth = 4      -- Number of spaces to use for auto-indents
vim.opt.expandtab = true    -- Use spaces instead of tabs

-- Enable line wrapping
vim.opt.wrap = false        -- Disable line wrapping (set to `true` to wrap lines)

-- Set search highlighting
vim.opt.hlsearch = true     -- Highlight search results
vim.opt.incsearch = true    -- Show incremental search results as you type

-- Enable 24-bit (true color) support
vim.opt.termguicolors = true

-- Enable clipboard support (works with system clipboard)
vim.opt.clipboard = "unnamedplus"  -- Use system clipboard (Linux/macOS)
-- For Windows, use:
-- vim.opt.clipboard = "unnamed"

-- Enable line numbers and relative numbers
vim.opt.number = true       -- Show line numbers
vim.opt.relativenumber = true -- Show relative line numbers (useful for movement)

-- Show cursor line (highlight the current line)
vim.opt.cursorline = true

-- Enable mouse support
vim.opt.mouse = "a"         -- Enable mouse support in all modes

-- Set search case insensitivity
vim.opt.ignorecase = true   -- Ignore case when searching
vim.opt.smartcase = true    -- But enable case-sensitive search if the search term contains uppercase letters

-- Enable auto indentation and smart indenting
vim.opt.smartindent = true
vim.opt.autoindent = true
vim.opt.expandtab = true    -- Use spaces instead of tabs
vim.opt.tabstop = 4         -- Set tab width to 4 spaces
vim.opt.shiftwidth = 4      -- Set indentation level to 4 spaces

-- Enable line numbers and disable netrw
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Enable smooth scrolling
vim.opt.scrolloff = 8        -- Keep 8 lines above and below the cursor when scrolling
vim.opt.sidescrolloff = 8    -- Keep 8 columns to the left/right of the cursor


-- Enable undo history
vim.opt.undofile = true      -- Enable undo history for persistent undo

-- Set maximum file size to avoid undo history for large files
vim.opt.undolevels = 1000    -- Set undo levels

-- Automatically read files when they change outside of vim
vim.opt.autoread = true

-- Set a timeout for mappings
vim.opt.timeoutlen = 500     -- Time (in milliseconds) to wait for a mapped sequence to complete








