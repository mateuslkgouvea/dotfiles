vim.pack.add { github 'stevearc/conform.nvim' }

require('conform').setup {
  notify_on_error = false,
  format_on_save = function(buffer)
    local enabled_filetypes = {
      -- lua = true,
      -- python = true,
    }
    if enabled_filetypes[vim.bo[buffer].filetype] then return { timeout_ms = 500 } end
  end,
  default_format_opts = { lsp_format = 'fallback' },
  formatters_by_ft = {
    html = { 'prettier' },
    javascript = { 'prettier' },
    javascriptreact = { 'prettier' },
    python = { 'ruff_format' },
    sql = { 'sqlfluff' },
  },
}
vim.keymap.set({ 'n', 'v' }, '<leader>f', function() require('conform').format { async = true } end, { desc = '[F]ormat buffer' })
