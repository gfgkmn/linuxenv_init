source $VIMRUNTIME/vimrc_example.vim
"source $VIMRUNTIME/mswin.vim
"behave mswin


set nocompatible              " be iMproved, required
filetype off                  " required

"----------set the runtime path to include Vundle and initialize-------------------
set rtp+=~/.vim/vundles/Vundle.vim
" alternatively, pass a path where Vundle should install plugins
set backup
set display=lastline
set showcmd
set backupdir=~/.vimbakfiles/
set undodir=~/.vimbakfiles/undofiles/
autocmd BufEnter * lcd %:p:h
colorscheme default

call vundle#begin("~/.vim/vundles")


"----------let Vundle manage Vundle, required-------------------
Plugin 'gmarik/Vundle.vim'

"----------get the plugins use vundle-------------------
" The following are examples of different formats supported.
" Keep Plugin commands between here and filetype plugin indent on.
" scripts on GitHub repos


" Plugin 'spolu/dwm'
" Plugin 'klen/python-mode'
" Plugin 'ivanov/vim-ipython'
Plugin 'jpalardy/vim-slime'
Plugin 'Lokaltog/vim-easymotion'
Plugin 'vim-scripts/fencview.vim'
Plugin 'vim-scripts/camelcasemotion'
" Plugin 'MattesGroeger/vim-bookmarks'
Plugin 'vim-scripts/LargeFile'
Plugin 'jiangmiao/auto-pairs'
" Plugin 'kana/vim-smartinput'
Plugin 'SirVer/ultisnips'
Plugin 'mbbill/undotree'
Plugin 'jmcantrell/vim-virtualenv'
Plugin 'Valloric/YouCompleteMe'
Plugin 'honza/vim-snippets'
Plugin 'kana/vim-textobj-user'
Plugin 'bps/vim-textobj-python'
Plugin 'kana/vim-textobj-indent'
Plugin 'kana/vim-textobj-line'
Plugin 'kana/vim-textobj-entire'
Plugin 'sgur/vim-textobj-parameter'
Plugin 'glts/vim-textobj-comment'
Plugin 'Julian/vim-textobj-variable-segment'
Plugin 'rizzatti/dash.vim'
Plugin 'kien/ctrlp.vim'
Plugin 'majutsushi/tagbar'
Plugin 'scrooloose/nerdtree'
Plugin 'terryma/vim-expand-region'
Plugin 'terryma/vim-multiple-cursors'
Plugin 'tpope/vim-commentary'
Plugin 'tpope/vim-repeat'
Plugin 'tpope/vim-surround'
Plugin 'tpope/vim-unimpaired'
Plugin 'vim-scripts/EasyGrep'
Plugin 'vim-scripts/TaskList.vim'
Plugin 'jlanzarotta/bufexplorer'
Plugin 'raymond-w-ko/vim-niji'

Plugin 'scrooloose/syntastic'

autocmd BufRead,BufNewFile *.clj set ft=clojure
" autocmd filetype clojure Plugin 'guns/vim-clojure-static'
" autocmd filetype clojure Plugin 'tpope/vim-fireplace'
Plugin 'guns/vim-clojure-static'
Plugin 'tpope/vim-fireplace'

autocmd BufRead,BufNewFile *.scala set ft=scala
" autocmd filetype scala Plugin 'derekwyatt/vim-scala'
" autocmd filetype scala Plugin 'ktvoelker/sbt-vim'
Plugin 'derekwyatt/vim-scala'
Plugin 'ktvoelker/sbt-vim'

" autocmd filetype c Plugin 'vim-scripts/cscope.vim'
" autocmd filetype c Plugin 'vim-scripts/CCTree'
" autocmd filetype c Plugin 'vim-scripts/a.vim'
Plugin 'vim-scripts/CCTree'
Plugin 'vim-scripts/a.vim'

call vundle#end()


"use youcompleteme replace cscope

" The sparkup vim script is in a subdirectory of this repo called vim.
" Pass the path to set the runtimepath properly.
"Plugin 'rstacruz/sparkup', {'rtp': 'vim/'}
" scripts from http://vim-scripts.org/vim/scripts.html


" scripts not on GitHub
"Plugin 'git://git.wincent.com/command-t.git'
" git repos on your local machine (i.e. when working on your own plugin)
"Plugin 'file:///home/gmarik/path/to/plugin'
" ...
filetype plugin indent on     " required
" To ignore plugin indent changes, instead use:
"filetype plugin on
"
" Brief help
" :PluginList          - list configured plugins
" :PluginInstall(!)    - install (update) plugins
" :PluginSearch(!) foo - search (or refresh cache first) for foo
" :PluginClean(!)      - confirm (or auto-approve) removal of unused plugins
"
" see :h vundle for more details or wiki for FAQ
" NOTE: comments after Plugin commands are not allowed.
" Put your stuff after this line

syntax on
filetype on
set foldmethod=indent
set encoding=utf-8
set termencoding=utf-8
set fileencoding=utf-8
set fileencodings=ucs-bom,utf-8,cp936,gb18030,big5,euc-jp,euc-kr,latin1
set foldlevel=100
set scs
hi normal guibg=#153948 guifg=white
set guifont=Monaco:h13
set number
set relativenumber
set ignorecase
set nosmartcase
set tag=./tags,tags,../tags,../../tags,../../../tags,/Users/gfgkmn/OpenSource/tags
set cst
runtime $VIMRUNTIME/macros/matchit.vim

"----------this is plugins's config-----------------------
"this is so strange, i need figure is out.
"set dictionary-=$VIM/vimfiles/otherfile/complete-dict dictionary+=$VIM/vimfiles/otherfile/complete-dict

"let g:neocomplcache_enable_ignore_case = 1
"nnoremap <silent> <F3> :Grep<CR>

"syntastic's config
let g:syntastic_python_checkers = ['flake8',  'pep8', 'Pylint']
let g:syntastic_check_on_wq = 0
let g:syntastic_auto_jump = 1
let g:syntastic_auto_loc_list = 1

"python-mode key's binding
let g:pymode_doc_bind = 'D'

"Tagbar's config
if !hasmapto(':TagbarToggle')
	map \tg :TagbarToggle<CR>
	map \ct :!ctags -R -f /Users/gfgkmn/OpenSource/tags `python -c "from distutils.sysconfig import get_python_lib; print get_python_lib()"`<CR>
endif

"Tagbar's config
if !hasmapto(':browse old')
	map \rf :browse old<CR>
endif


"Tagbar's config
if !hasmapto(':cclose | pclose | SyntasticReset')
	map \ca :cclose <bar> pclose <bar> SyntasticReset <bar> nohl<CR>
endif

" NerdTree's keymappint
if !hasmapto(':NERDTreeToggle')
	map \nt :NERDTreeToggle<CR>
endif

" bookmarking's keymapping
if !hasmapto(':ToggleBookmark')
	map \mt :ToggleBookmark<CR>
endif

" dash's keymapping
if !hasmapto(':DashSearch')
	nmap <silent> <leader>d <Plug>DashSearch
endif

if !hasmapto(':NextBookmark')
	map \mn :NextBookmark<CR>
endif

if !hasmapto(':PreviousBookmark')
	map \mp :PreviousBookmark<CR>
endif
"Gundo's keymapping
if !hasmapto(':UndotreeToggle')
	map \gt :UndotreeToggle<CR>
endif
"TaskList's keymapping
map \td <Plug>TaskList

"YouCompleteMe's config
" if exists("EnableYouCompleteMe")
	let g:ycm_complete_in_comments = 1
	let g:ycm_min_num_of_chars_for_completion = 3
	let g:ycm_key_invoke_completion = '<C-S-k>'
	let g:ycm_key_list_select_completion = ['<tab>', '<Down>']
	let g:ycm_key_list_previous_completion = ['<s-tab>', '<Up>']
	" let g:ycm_global_ycm_extra_conf = "$VIM\\vundles\\YouCompleteMe\\extra_py\\.ycm_extra_conf.py"
	nnoremap <leader>gl :YcmCompleter GoToDeclaration<CR>
	nnoremap <leader>gf :YcmCompleter GoToDefinition<CR>
	nnoremap <leader>gg :YcmCompleter GoToDefinitionElseDeclaration<CR>
	nnoremap <leader>gr :YcmCompleter GoToReferences<CR>
	nnoremap <leader>gd :YcmCompleter GetDoc<CR>
" endif

"UltiSnips config
let g:UltiSnipsListSnippets = "<c-l>"
" Trigger configuration. 
let g:UltiSnipsExpandTrigger="<c-j>"
"let g:UltiSnipsJumpForwardTrigger="<c-j>"
"let g:UltiSnipsJumpBackwardTrigger="<c-k>"

"vim-slime's config
let g:slime_target = 'tmux'
let g:slime_python_ipython = 1
let g:slime_default_config = {"socket_name": "default", "target_pane": ":"}
let g:slime_dont_ask_default = 1
noremap <leader>s :SlimeSend<CR>

"minibufexpl's config
"----------this is myself key-binding for jump between different subwindows.
noremap <C-Left> <C-w>h
noremap <C-Right> <C-w>l
noremap <C-Up> <C-w>k
noremap <C-Down> <C-w>j
"this nerdtree's key-binding jumptonextslibing has conflict with minibuf's navigation
noremap <C-h> <C-w>h
noremap <C-l> <C-w>l
noremap <C-k> <C-w>k
noremap <C-j> <C-w>j

" syntastic check key-binding
noremap <leader>ch :SyntasticCheck<CR>
noremap <leader>ck :SyntasticReset<CR>
noremap <leader>co :copen<CR>
noremap <leader>cq :cclose<CR>

" yapf key-binding
noremap <leader>cf :call yapf#YAPF()<cr>

autocmd FileType c iabbrev \s //-->>
autocmd FileType c iabbrev \e //<<--
autocmd FileType c iabbrev \w //--==--
autocmd FileType c iabbrev \y //--?>:
autocmd FileType c iabbrev \: //:test:
autocmd FileType c iabbrev \i //:]--
autocmd FileType python iabbrev \s #-->>
autocmd FileType python iabbrev \e #<<--
autocmd FileType python iabbrev \w #--==--
autocmd FileType python iabbrev \y #--?>:
autocmd FileType python iabbrev \: #:test:
autocmd FileType python iabbrev \i #:]--

" i don's which's this config
noremap <leader>ol :browse oldfiles<CR>

"----------this is python's config----------------------
set diffopt=filler,context:3
autocmd FileType python setlocal et sta sw=4 sts=4
autocmd FileType python setlocal foldmethod=indent
set foldlevel=99
