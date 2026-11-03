local telescope_plugins = {
  github 'nvim-lua/plenary.nvim',
  github 'nvim-telescope/telescope.nvim',
  github 'nvim-telescope/telescope-ui-select.nvim',
  github 'hedyhli/outline.nvim',
}
if vim.fn.executable 'make' == 1 then
  table.insert(telescope_plugins, github 'nvim-telescope/telescope-fzf-native.nvim')
end
vim.pack.add(telescope_plugins)

local telescope = require('telescope')
telescope.setup { extensions = { ['ui-select'] = { require('telescope.themes').get_dropdown() } } }
pcall(telescope.load_extension, 'fzf')
pcall(telescope.load_extension, 'ui-select')

require('outline').setup {}

local builtin = require 'telescope.builtin'
local mappings = {
  ['<leader>sh'] = { builtin.help_tags, '[S]earch [H]elp' },
  ['<leader>sk'] = { builtin.keymaps, '[S]earch [K]eymaps' },
  ['<leader>sf'] = { builtin.find_files, '[S]earch [F]iles' },
  ['<leader>ss'] = { builtin.builtin, '[S]earch [S]elect Telescope' },
  ['<leader>sg'] = { builtin.live_grep, '[S]earch by [G]rep' },
  ['<leader>sd'] = { builtin.diagnostics, '[S]earch [D]iagnostics' },
  ['<leader>sr'] = { builtin.resume, '[S]earch [R]esume' },
  ['<leader>s.'] = { builtin.oldfiles, '[S]earch Recent Files' },
  ['<leader>sc'] = { builtin.commands, '[S]earch [C]ommands' },
  ['<leader><leader>'] = { builtin.buffers, '[ ] Find existing buffers' },
}
for key, mapping in pairs(mappings) do
  vim.keymap.set('n', key, mapping[1], { desc = mapping[2] })
end
vim.keymap.set({ 'n', 'v' }, '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
vim.keymap.set('n', '<leader>sn', function() builtin.find_files { cwd = vim.fn.stdpath 'config' } end, { desc = '[S]earch [N]eovim files' })
vim.keymap.set('n', '<leader>/', function() builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown { previewer = false }) end, { desc = 'Search current buffer' })
vim.keymap.set('n', '<leader>o', '<cmd>Outline<CR>', { desc = 'Toggle outline' })
