vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic quickfix list' })
vim.keymap.set('n', '<S-h>', '<cmd>bprevious<CR>', { desc = 'Previous buffer' })
vim.keymap.set('n', '<S-l>', '<cmd>bnext<CR>', { desc = 'Next buffer' })
vim.keymap.set('n', '<leader>bd', '<cmd>bdelete<CR>', { desc = 'Delete current buffer' })
vim.keymap.set('n', '<leader>bo', function()
	local current = vim.api.nvim_get_current_buf()
	local skipped = {}

	for _, buffer in ipairs(vim.fn.getbufinfo { buflisted = 1 }) do
		if buffer.bufnr ~= current then
			if vim.bo[buffer.bufnr].modified then
				table.insert(skipped, tostring(buffer.bufnr))
			else
				local ok = pcall(vim.api.nvim_buf_delete, buffer.bufnr, {})
				if not ok then table.insert(skipped, tostring(buffer.bufnr)) end
			end
		end
	end

	if #skipped > 0 then
		vim.notify('Kept modified buffer(s): ' .. table.concat(skipped, ', '), vim.log.levels.WARN)
	end
end, { desc = 'Delete other buffers' })

vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })
