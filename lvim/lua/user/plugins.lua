lvim.plugins = {
    {
        'nvim-lualine/lualine.nvim',
        dependencies = 'nvim-tree/nvim-web-devicons',
        config = function()
          require('user/plugins/lualine')
        end,
    },
}

lvim.builtin.lualine.style = "default"
