vim.pack.add { github 'nvim-tree/nvim-tree.lua' }

local function nvim_tree_on_attach(bufnr)
  local api = require("nvim-tree.api")
  -- Keep all the normal nvim-tree mappings
  api.map.on_attach.default(bufnr)
  local opts = { buffer = bufnr, noremap = true, silent = true, nowait = true }
  vim.keymap.set('n', 'l', api.node.open.edit, vim.tbl_extend('force', opts, { desc = 'Open' }))
  vim.keymap.set('n', 'h', api.node.navigate.parent_close, vim.tbl_extend('force', opts, { desc = 'Close directory' }))
end

require('nvim-tree').setup {
  sort = {
    sorter = "case_sensitive",
  },
  view = {
    width = 30,
  },
  renderer = {
    icons = {
      show = {
        file = true,
        folder = true,
        folder_arrow = true,
        git = true,
        modified = true,
        diagnostics = true,
        bookmarks = true,
      },
    },
  },
  on_attach = nvim_tree_on_attach,
}

vim.keymap.set('n', '<leader>e', '<cmd>NvimTreeToggle<CR>', { desc = 'Toggle file tree' })
