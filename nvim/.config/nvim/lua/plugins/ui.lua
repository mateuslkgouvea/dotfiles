vim.pack.add {
  github 'NMAC427/guess-indent.nvim',
  github 'lewis6991/gitsigns.nvim',
  github 'folke/which-key.nvim',
  github 'folke/tokyonight.nvim',
  github 'folke/todo-comments.nvim',
  github 'nvim-mini/mini.nvim',
  github 'kdheepak/lazygit.nvim',
  github 'chentoast/marks.nvim',
}

require('guess-indent').setup {}
local gitsigns = require('gitsigns')
gitsigns.setup {
  signs = {
    add = { text = '+' }, change = { text = '~' }, delete = { text = '_' },
    topdelete = { text = '‾' }, changedelete = { text = '~' },
  },
  on_attach = function(buffer)
    vim.keymap.set('n', ']c', gitsigns.next_hunk, { buffer = buffer, desc = 'Next git change' })
    vim.keymap.set('n', '[c', gitsigns.prev_hunk, { buffer = buffer, desc = 'Previous git change' })
    vim.keymap.set('n', '<leader>hs', gitsigns.stage_hunk, { buffer = buffer, desc = 'Stage git hunk' })
    vim.keymap.set('n', '<leader>hr', gitsigns.reset_hunk, { buffer = buffer, desc = 'Reset git hunk' })
    vim.keymap.set('n', '<leader>hp', gitsigns.preview_hunk, { buffer = buffer, desc = 'Preview git hunk' })
    vim.keymap.set('n', '<leader>hb', function() gitsigns.blame_line { full = true } end, { buffer = buffer, desc = 'Blame line' })
  end,
}
vim.keymap.set('n', '<leader>gg', '<cmd>LazyGitCurrentFile<CR>', { desc = 'Open LazyGit (repository)' })
vim.keymap.set('n', '<leader>gG', '<cmd>LazyGit<CR>', { desc = 'Open LazyGit (working directory)' })
vim.keymap.set('n', '<leader>gf', '<cmd>LazyGitFilterCurrentFile<CR>', { desc = 'File git history' })
vim.keymap.set('n', '<leader>gl', '<cmd>LazyGitFilter<CR>', { desc = 'Repository git history' })
vim.keymap.set('n', '<leader>gC', '<cmd>LazyGitConfig<CR>', { desc = 'Open LazyGit config' })

require('marks').setup {
  builtin_marks = { '.', '<', '>', '^' },
}

require('which-key').setup {
  delay = 500,
  icons = { mappings = vim.g.have_nerd_font },
  spec = {
    { '<leader>g', group = '[G]it' },
    { '<leader>s', group = '[S]earch' },
    { '<leader>h', group = 'Git [H]unk' },
    { '<leader>t', group = '[T]oggle' },
  },
}
require('tokyonight').setup { styles = { comments = { italic = false } } }
vim.cmd.colorscheme 'tokyonight-night'
require('todo-comments').setup { signs = false }

if vim.g.have_nerd_font then
  require('mini.icons').setup()
  MiniIcons.mock_nvim_web_devicons()
end
require('mini.ai').setup { n_lines = 500 }
require('mini.surround').setup()
require('mini.statusline').setup { use_icons = vim.g.have_nerd_font }
require('mini.tabline').setup { show_icons = vim.g.have_nerd_font }

local statusline = require('mini.statusline')
statusline.section_location = function() return '%2l:%-2v' end
