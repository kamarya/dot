" Neovim configuration
" Converted from vim/vimrc (guioptions and the terminal cursor-escape
" fallback were dropped since Neovim doesn't use classic GUI options and
" handles cursor shape via 'guicursor' natively)

" Syntax highlighting and filetype-aware indent/plugins for all
" recognized languages (.c, .cpp, .hpp, .rs, .go, etc.) -- on by
" default in Neovim, set explicitly here for parity with vim/vimrc
syntax on
filetype plugin indent on

" Leader key
let mapleader = ","

" Don't dawdle after Esc waiting for a possible key-code sequence
set ttimeout
set ttimeoutlen=10

" Ignore case when searching
set ignorecase

" When searching try to be smart about cases
set smartcase

" Highlight search results
set hlsearch

" Makes search act like search in modern browsers
set incsearch

" Don't redraw while executing macros (good performance config)
set lazyredraw

" For regular expressions turn magic on
set magic

" Show matching brackets when text indicator is over them
set showmatch

" Turn backup off, since most stuff is in SVN, git etc. anyway...
set nobackup
set nowritebackup
set noswapfile

" Linebreak on 500 characters
set linebreak
set textwidth=500

set autoindent
set smartindent
set wrap

set number

" Highlight the screen line of the cursor
set cursorline

set background=dark
set termguicolors
colorscheme kamary

" Cursor shape: blinking vertical bar in insert mode only, steady block otherwise
set guicursor=n-v-c-sm:block,i-ci-ve:ver25-blinkon400-blinkoff250,r-cr-o:hor20

" Restore terminal to a steady block cursor when nvim exits
augroup RestoreCursorShape
  autocmd!
  autocmd VimLeave * silent !echo -ne "\e[2 q"
augroup END
