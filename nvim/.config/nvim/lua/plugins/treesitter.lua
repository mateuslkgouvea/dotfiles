vim.pack.add { { src = github 'nvim-treesitter/nvim-treesitter', version = 'main' } }

local treesitter = require('nvim-treesitter')
treesitter.install { 'bash', 'c', 'css', 'diff', 'html', 'javascript', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'sql', 'vim', 'vimdoc' }

local function attach(buf, language)
  if not vim.treesitter.language.add(language) or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.treesitter.start(buf, language)
  if vim.treesitter.query.get(language, 'indents') then
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('config-treesitter', { clear = true }),
  callback = function(event)
    local language = vim.treesitter.language.get_lang(event.match)
    if not language then return end
    if vim.tbl_contains(treesitter.get_installed 'parsers', language) then
      attach(event.buf, language)
    elseif vim.tbl_contains(treesitter.get_available(), language) then
      treesitter.install(language):await(function() attach(event.buf, language) end)
    else
      attach(event.buf, language)
    end
  end,
})
