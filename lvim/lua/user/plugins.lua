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
        'nvim-treesitter/nvim-treesitter',
        build = function()
          require('nvim-treesitter.install').update({ with_sync = true })
        end,
        dependencies = {
          'nvim-treesitter/playground',
          'JoosepAlviste/nvim-ts-context-commentstring',
          'nvim-treesitter/nvim-treesitter-textobjects',
        },
        config = function()
          require('user/plugins/treesitter')
        end,
    },
    {
        'neovim/nvim-lspconfig',
        dependencies = {
          'williamboman/mason.nvim',
          'williamboman/mason-lspconfig.nvim',
          'b0o/schemastore.nvim',
          'jose-elias-alvarez/null-ls.nvim',
          'jayp0521/mason-null-ls.nvim',
        },
        config = function()
          require('user/plugins/lspconfig')
        end,
    },
    {
        'hrsh7th/nvim-cmp',
        dependencies = {
          'hrsh7th/cmp-nvim-lsp',
          'hrsh7th/cmp-nvim-lsp-signature-help',
          'hrsh7th/cmp-buffer',
          'hrsh7th/cmp-path',
          'L3MON4D3/LuaSnip',
          'saadparwaiz1/cmp_luasnip',
          'onsails/lspkind-nvim',
        },
        config = function()
          require('user/plugins/cmp')
        end,
    },
    {
        'nvim-lualine/lualine.nvim',
--         after = 'tokyonight.nvim',
        dependencies = {
          'arkav/lualine-lsp-progress',
          'nvim-tree/nvim-web-devicons',
        },
        config = function()
          require('user/plugins/lualine')
        end,
    },
    {
        'akinsho/bufferline.nvim',
        dependencies = 'nvim-tree/nvim-web-devicons',
--        after = 'onedark.nvim',
        config = function()
          require('user/plugins/bufferline')
        end,
    },
    {
        'lukas-reineke/indent-blankline.nvim',
        config = function()
          require('user/plugins/indent-blankline')
        end,
    }
}
