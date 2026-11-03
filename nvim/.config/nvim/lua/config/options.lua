vim.loader.enable()

vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.g.have_nerd_font = true
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

local options = {
  tabstop = 4,
  shiftwidth = 4,
  expandtab = true,
  softtabstop = 4,
  number = true,
  relativenumber = true,
  mouse = 'a',
  showmode = false,
  breakindent = true,
  undofile = true,
  ignorecase = true,
  smartcase = true,
  signcolumn = 'yes',
  updatetime = 250,
  timeoutlen = 300,
  splitright = true,
  splitbelow = true,
  list = true,
  inccommand = 'split',
  cursorline = true,
  scrolloff = 10,
  confirm = true,
}

for name, value in pairs(options) do
  vim.opt[name] = value
end

vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
