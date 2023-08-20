lvim.plugins = {
    {
        "voldikss/vim-floaterm",
        config = function()
          vim.g.floaterm_width = 0.8
          vim.g.floaterm_height = 0.8
          vim.keymap.set('n', '<F1>', ':FloatermToggle<CR>')
          vim.keymap.set('t', '<F1>', '<C-\\><C-n>:FloatermToggle<CR>')
        end
    },
    {
        'nvim-lualine/lualine.nvim',
        dependencies = 'nvim-tree/nvim-web-devicons',
        config = function()
          require('user/plugins/lualine')
        end,
    },
}

lvim.builtin.lualine.style = "default"
