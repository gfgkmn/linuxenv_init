source $VIMRUNTIME/vimrc_example.vim
"source $VIMRUNTIME/mswin.vim
"behave mswin


set nocompatible              " be iMproved, required
filetype off                  " required

"----------set the runtime path to include Vundle and initialize-------------------
set rtp+=~/.vim/vundles/vim-plug
" alternatively, pass a path where Vundle should install plugins
set backup
set display=lastline
set showcmd
set backupdir=~/.vimbakfiles/
" set undodir=~/.vimbakfiles/undofiles/
set exrc
set secure
" autocmd BufEnter * lcd %:p:h

" call vundle#begin("~/.vim/vundles")
call plug#begin('~/.vim/vundles')


"----------let Vundle manage Vundle, required-------------------
Plug 'git@github.com:junegunn/vim-plug.git'

"----------get the plugins use vundle-------------------
" The following are examples of different formats supported.
" Keep Plugin commands between here and filetype plugin indent on.
" scripts on GitHub repos


" Plugin 'spolu/dwm'
" Plugin 'klen/python-mode'
" Plugin 'ivanov/vim-ipython'
Plug 'git@github.com:jpalardy/vim-slime.git'
Plug 'git@github.com:xolox/vim-misc.git'
Plug 'git@github.com:xolox/vim-notes.git'
Plug 'git@github.com:xolox/vim-session.git'
Plug 'git@github.com:Lokaltog/vim-easymotion.git'
Plug 'git@github.com:vim-scripts/fencview.vim.git'
Plug 'git@github.com:vim-scripts/camelcasemotion.git'
Plug 'git@github.com:vim-scripts/LargeFile.git'
Plug 'git@github.com:jiangmiao/auto-pairs.git'
Plug 'git@github.com:vim-scripts/matchit.zip.git'
" Plugin 'git@github.com:kana/vim-smartinput.git'
Plug 'git@github.com:SirVer/ultisnips.git'
Plug 'git@github.com:mbbill/undotree.git'
Plug 'git@github.com:tpope/vim-fugitive.git'
Plug 'git@github.com:airblade/vim-gitgutter.git'
Plug 'git@github.com:jmcantrell/vim-virtualenv.git'
" Plug 'git@github.com:Valloric/YouCompleteMe.git'
Plug 'git@github.com:rdnetto/YCM-Generator', { 'git@github.com:branch': 'git@github.com:stable' }
Plug 'git@github.com:honza/vim-snippets.git'
Plug 'git@github.com:kana/vim-textobj-user.git'
Plug 'git@github.com:bps/vim-textobj-python.git'
Plug 'git@github.com:kana/vim-textobj-indent.git'
Plug 'git@github.com:kana/vim-textobj-line.git'
Plug 'git@github.com:kana/vim-textobj-entire.git'
Plug 'git@github.com:sgur/vim-textobj-parameter.git'
Plug 'git@github.com:glts/vim-textobj-comment.git'
Plug 'git@github.com:Julian/vim-textobj-variable-segment.git'
Plug 'git@github.com:rizzatti/dash.vim.git'
Plug 'git@github.com:kien/ctrlp.vim.git'
Plug 'git@github.com:mhinz/vim-startify.git'
Plug 'git@github.com:majutsushi/tagbar.git'
Plug 'git@github.com:scrooloose/nerdtree.git'
Plug 'git@github.com:terryma/vim-expand-region.git'
Plug 'git@github.com:terryma/vim-multiple-cursors.git'
Plug 'git@github.com:tpope/vim-commentary.git'
Plug 'git@github.com:tpope/vim-repeat.git'
Plug 'git@github.com:tpope/vim-surround.git'
Plug 'git@github.com:tpope/vim-unimpaired.git'
Plug 'git@github.com:mhinz/vim-grepper.git'
Plug 'git@github.com:vim-scripts/TaskList.vim.git'
Plug 'git@github.com:jlanzarotta/bufexplorer.git'
Plug 'git@github.com:vim-scripts/WhereFrom.git'
" Plugin 'git@github.com:lervag/vimtex.git'
" Plugin 'git@github.com:itchyny/calendar.vim.git'
Plug 'git@github.com:vimwiki/vimwiki.git'

Plug 'git@github.com:scrooloose/syntastic.git'

Plug 'git@github.com:guns/vim-clojure-static.git', {'for': 'clojure'}
Plug 'git@github.com:tpope/vim-fireplace.git', {'for': 'clojure'}
Plug 'git@github.com:raymond-w-ko/vim-niji.git', {'for': 'clojure'}

Plug 'git@github.com:derekwyatt/vim-scala.git', {'for': 'scala'}
Plug 'git@github.com:ktvoelker/sbt-vim.git', {'for': 'scala'}

Plug 'git@github.com:vim-scripts/CCTree.git'
Plug 'git@github.com:Chiel92/vim-autoformat.git'

Plug 'git@github.com:leafgarland/typescript-vim.git', {'for': 'typescript'}
Plug 'git@github.com:Quramy/tsuquyomi.git', {'for': 'typescript'}
Plug 'git@github.com:Shougo/vimproc.vim.git', {'for': 'typescript', 'do': 'make'}

call plug#end()


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
set scrolloff=3
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
nmap gs  <plug>(GrepperOperator)
xmap gs  <plug>(GrepperOperator)
nnoremap <leader>vr :Grepper<cr>
let g:grepper = { 'next_tool': '<leader>g' }
nnoremap <leader>vv :Grepper -tool grep -cword -noprompt<CR>

"syntastic's config
let g:syntastic_python_checkers = ['flake8',  'pep8', 'Pylint']
" let g:syntastic_mode_map = {'model': 'passive', 'passive_filetypes': ['python', 'objc', 'c']}
let g:syntastic_check_on_wq = 1
let g:syntastic_auto_jump = 1
let g:syntastic_auto_loc_list = 1
noremap \cy :SyntasticToggleMode<CR>

"python-mode key's binding
let g:pymode_doc_bind = 'D'

"Tagbar's config
if !hasmapto(':TagbarToggle')
	map \tg :TagbarToggle<CR>
	map \ct :!ctags -R -f /Users/gfgkmn/OpenSource/tags `python -c "from distutils.sysconfig import get_python_lib; print get_python_lib()"`<CR>

	let g:tagbar_type_objc = {
				\ 'ctagstype' : 'ObjectiveC',
				\ 'kinds'     : [
				\ 'i:interface',
				\ 'I:implementation',
				\ 'p:Protocol',
				\ 'm:Object_method',
				\ 'c:Class_method',
				\ 'v:Global_variable',
				\ 'F:Object field',
				\ 'f:function',
				\ 'p:property',
				\ 't:type_alias',
				\ 's:type_structure',
				\ 'e:enumeration',
				\ 'M:preprocessor_macro',
				\ ],
				\ 'sro'        : ' ',
				\ 'kind2scope' : {
				\ 'i' : 'interface',
				\ 'I' : 'implementation',
				\ 'p' : 'Protocol',
				\ 's' : 'type_structure',
				\ 'e' : 'enumeration'
				\ },
				\ 'scope2kind' : {
				\ 'interface'      : 'i',
				\ 'implementation' : 'I',
				\ 'Protocol'       : 'p',
				\ 'type_structure' : 's',
				\ 'enumeration'    : 'e'
				\ }
				\ }
	" let g:tagbar_type_objc = {
	" 			\  'ctagstype': 'objc'
	" 			\, 'ctagsargs': [
	" 			\   '--options='.expand('~/.vim/objctags')
	" 			\,  '--objc-kinds=-N'
	" 			\,  '--format=2'
	" 			\,  '--excmd=pattern'
	" 			\,  '--extra='
	" 			\,  '--fields=nksaSmte'
	" 			\,  '-f -'
	" 			\]
	" 			\, 'kinds': [
	" 			\     'i:class interface'
	" 			\,    'x:class extension'
	" 			\,    'I:class implementation'
	" 			\,    'P:protocol'
	" 			\,    'M:method'
	" 			\,    't:typedef'
	" 			\,    'v:variable'
	" 			\,    'p:property'
	" 			\,    'e:enumeration'
	" 			\,    'f:function'
	" 			\,    'd:macro'
	" 			\,    'g:pragma'
	" 			\,    'c:constant'
	" 			\, ]
	" 			\, 'sro': ' '
	" 			\}
endif

if !hasmapto(':TagbarTogglePause')
	map \lt :TagbarTogglePause<CR>
endif

"Tagbar's config
if !hasmapto(':browse old')
	map \rf :browse old<CR>
endif

"matchit config
if exists("loaded_matchit")
  let b:match_ignorecase=0
  let b:match_words=
    \ '\<begin\>:\<end\>,' .
    \ '\<case\>\|\<casex\>\|\<casez\>:\<endcase\>,' .
    \ '\<module\>:\<endmodule\>,' .
    \ '\<if\>:\<else\>,' .
    \ '\<function\>:\<endfunction\>,' .
    \ '`ifdef\>:`else\>:`endif\>,' .
    \ '\<task\>:\<endtask\>,' .
    \ '\<specify\>:\<endspecify\>'
endif


"Tagbar's config
if !hasmapto(':cclose | pclose | SyntasticReset | nohl | :TagbarClose')
	map \ca :cclose <bar> pclose <bar> SyntasticReset <bar> nohl <bar> :UndotreeHide <bar> :TagbarClose <bar> :lclose <CR>
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
let g:ycm_show_diagnostics_ui = 0
" allow syntastic checker for objc to run
let g:ycm_key_invoke_completion = '<C-S-k>'
let g:ycm_key_list_select_completion = ['<tab>', '<Down>']
let g:ycm_key_list_previous_completion = ['<s-tab>', '<Up>']
let g:ycm_global_ycm_extra_conf = "~/.vim/vundles/YouCompleteMe/third_party/ycmd/cpp/ycm/.ycm_extra_conf.py"
nnoremap <leader>gf :YcmCompleter GoToDeclaration<CR>
nnoremap <leader>gg :YcmCompleter GoToDefinition<CR>
nnoremap <leader>gl :YcmCompleter GoToDefinitionElseDeclaration<CR>
nnoremap <leader>gr :YcmCompleter GoToReferences<CR>
nnoremap <leader>gd :YcmCompleter GetDoc<CR>

if !exists("g:ycm_semantic_triggers")
	let g:ycm_semantic_triggers = {}
endif
let g:ycm_semantic_triggers['typescript'] = ['.']

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
noremap <leader>ss :%SlimeSend<CR>

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


" about function defined
function! GotoJump()
	jumps
	let j = input("Please select your jump: ")
	if j != ''
		let pattern = '\v\c^\+'
		if j =~ pattern
			let j = substitute(j, pattern, '', 'g')
			execute "normal " . j . "\<c-i>"
		else
			execute "normal " . j . "\<c-o>"
		endif
	endif
endfunction"

nmap <Leader>f :call GotoJump()<CR>
nmap <leader>r :!%:p<CR>

" syntastic check key-binding
noremap <leader>ch :SyntasticCheck<CR>
noremap <leader>ck :SyntasticReset<CR>
noremap <leader>co :copen<CR>
noremap <leader>cq :cclose<CR>

" i don's which's this config
noremap <leader>ol :browse oldfiles<CR>
noremap <leader>cf :call yapf#YAPF()<cr>

" autoformat config
" noremap <leader>cf :Autoformat<CR>
" let g:formatter_yapf_style = 'pep8'

" vim-session config
let g:session_autosave = 'yes'
let g:session_autoload = 'no'
let g:session_command_aliases = 1

" vim-notes config
let g:notes_directories = ['~/Documents/Vim-notes']

" treat crontab as normal file
if $VIM_CRONTAB == "true"
	set nobackup
	set nowritebackup
endif

"switch header file and objc file
map \a :e %:p:s,.h$,.X123X,:s,.m$,.h,:s,.X123X$,.m,<CR>

"----------this is python's config----------------------
set diffopt=filler,context:3
autocmd FileType python setlocal et sta sw=4 sts=4
autocmd FileType objc setlocal et sta sw=4 sts=4
autocmd FileType python setlocal foldmethod=indent
autocmd FileType python setlocal foldmethod=manual
autocmd FileType python nmap <leader>r :!python %<CR>
autocmd FileType lua nmap <leader>r :!lua %<CR>
set foldlevel=99
