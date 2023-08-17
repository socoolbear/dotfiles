set nocompatible              "We want the latest Vim settings/options.
set belloff=all
set rtp+=/opt/homebrew/opt/fzf

so ~/.vim/plugins.vim

"------------------Default-----------------------"
syntax enable
set backspace=indent,eol,start
let mapleader = ','              "The default leader is `\` , but a commaa is much batter. 
set number                       "Let's activate line numbers. 

"------------------Visuals-----------------------"
colorscheme atom-dark
set t_CO=256
set linespace=15                 "Macvim-specific line-height
set gfn=Monaco:h18               "Macvim
set guioptions=l
set guioptions=L
set guioptions=r
set guioptions=R

"------------------Search-----------------------"
set nohlsearch
set incsearch


"------------------Split Management-----------------------"
set splitbelow
set splitright

nmap <C-J> <C-W><C-J>
nmap <C-K> <C-W><C-K>
nmap <C-H> <C-W><C-H>
nmap <C-L> <C-W><C-L>

"------------------Mappings-----------------------"

" Make it easy to edit the Vimrc file.
nmap <Leader>ev :tabedit $MYVIMRC <CR> " be iMproved, required ,ev :e ~/.vimrc

"Add simple highligth removal.
nmap <Leader><space> :nohlsearch <CR>

"Make NERDTree easier to toggle.
nmap <D-1> :NERDTreeToggle <CR>

"nmap <C-R> :CtrlPBufTag <CR>
"nmap <D-e> :CtrlPMRUFiles <CR>


"------------------Plugins------------------"

"/
"/ CtrlP
"/
let g:ctrlp_custom_ignore = "node_modules\DS_Storage\|git"
let g:ctrlp_match_window = "top,order:ttb,min:1,max:30,result:30"

"------------------Auto-Commands------------------"

"Automatically source the Vimrc file on save.
augroup autosourcing
        autocmd!
        autocmd BufWritePost .vimrc source %
augroup END

set expandtab
set tabstop=4
set shiftwidth=4
set autoindent

"syn on
"set ignorecase smartcase

au Bufenter *.\(c\|cpp\|h\|php\) set et
au Bufenter *.\(html\|js\|css\) set et
au Bufenter *.\(html\|js\|css\) set shiftwidth=2
au Bufenter *.\(html\|js\|css\) set tabstop=2




" set clipboard=unnamed



"------------------Short Cut Memo-----------------------"
"<C-w> |,  <C-w> H  "Collapse

" ---------- Custom Hotkeys -
:set iskeyword-=_
:nmap <leader>s :split<Cr>
:nmap <leader>vs :vsplit<Cr>
nnoremap [[ [mzz
nnoremap ]] ]mzz