vim.pack.add {
  github 'j-hui/fidget.nvim',
  github 'neovim/nvim-lspconfig',
  github 'mason-org/mason.nvim',
  github 'mason-org/mason-lspconfig.nvim',
  github 'WhoIsSethDaniel/mason-tool-installer.nvim',
}
require('fidget').setup {}
require('mason').setup {}
require('mason-lspconfig').setup { automatic_enable = false }

local function javascript_root(bufnr, on_dir)
  local root_markers = {
    { 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb', 'bun.lock', '.clasp.json' },
    { '.git' },
  }
  local root = vim.fs.root(bufnr, root_markers)
  local deno_root = vim.fs.root(bufnr, { 'deno.json', 'deno.jsonc' })
  local deno_lock_root = vim.fs.root(bufnr, 'deno.lock')

  if (deno_root and (not root or #deno_root >= #root)) or (deno_lock_root and (not root or #deno_lock_root > #root)) then
    return
  end
  on_dir(root or vim.fn.getcwd())
end

local html_capabilities = vim.lsp.protocol.make_client_capabilities()
html_capabilities.textDocument.completion.completionItem.snippetSupport = true

-- Add a server here, then add its package name to `ensure_installed` when needed.
local servers = {
  ts_ls = {
    root_dir = javascript_root,
  },
  html = {
    root_markers = { '.clasp.json', 'package.json', '.git' },
    capabilities = html_capabilities,
  },
  ruff = {
    init_options = {
      settings = {
        organizeImports = true,
        fixAll = true,
      },
    },
  },
  basedpyright = {
    settings = {
      basedpyright = { analysis = { typeCheckingMode = 'basic' } },
    },
  },
  sqls = {},
  lua_ls = {
    on_init = function(client)
      client.server_capabilities.documentFormattingProvider = false
      local folders = client.workspace_folders
      if folders and folders[1] and folders[1].name ~= vim.fn.stdpath 'config' then
        local path = folders[1].name
        if vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc') then return end
      end
      client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua or {}, {
        runtime = { version = 'LuaJIT', path = { 'lua/?.lua', 'lua/?/init.lua' } },
        workspace = { checkThirdParty = false, library = vim.api.nvim_get_runtime_file('', true) },
      })
    end,
    settings = { Lua = { format = { enable = false } } },
  },
}

require('mason-tool-installer').setup {
  ensure_installed = {
    'basedpyright',
    'html-lsp',
    'lua-language-server',
    'prettier',
    'ruff',
    'sqls',
    'sqlfluff',
    'stylua',
    'typescript-language-server',
  },
}
for name, config in pairs(servers) do
  vim.lsp.config(name, config)
  vim.lsp.enable(name)
end

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('config-lsp-attach', { clear = true }),
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    local builtin = require 'telescope.builtin'
    local function map(keys, action, description, mode)
      vim.keymap.set(mode or 'n', keys, action, { buffer = event.buf, desc = 'LSP: ' .. description })
    end

    map('grn', vim.lsp.buf.rename, 'Rename')
    map('gra', vim.lsp.buf.code_action, 'Code action', { 'n', 'x' })
    map('grD', vim.lsp.buf.declaration, 'Go to declaration')
    map('grr', builtin.lsp_references, 'Go to references')
    map('gri', builtin.lsp_implementations, 'Go to implementation')
    map('grd', builtin.lsp_definitions, 'Go to definition')
    map('grt', builtin.lsp_type_definitions, 'Go to type definition')
    map('gO', builtin.lsp_document_symbols, 'Open document symbols')
    map('gW', builtin.lsp_dynamic_workspace_symbols, 'Open workspace symbols')
    if client and client:supports_method('textDocument/inlayHint', event.buf) then
      map('<leader>th', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf }) end, 'Toggle inlay hints')
    end
  end,
})
