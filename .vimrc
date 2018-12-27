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
set undodir=~/.vimbakfiles/undofiles/
" set path+=/usr/local/Cellar/llvm/6.0.0/include/c++/v1
set exrc
set secure
" set macmeta
" autocmd BufEnter * lcd %:p:h
autocmd FocusGained * :redraw!
colorscheme gfgkmn
if &diff
    colorscheme default
endif

" call vundle#begin("~/.vim/vundles")
call plug#begin('~/.vim/vundles')


"----------let Vundle manage Vundle, required-------------------
Plug 'junegunn/vim-plug'

"----------get the plugins use vundle-------------------
" The following are examples of different formats supported.
" Keep Plugin commands between here and filetype plugin indent on.
" scripts on GitHub repos

function! BuildYCM(info)
	" info is a dictionary with 3 fields
	" - name:   name of the plugin
	" - status: 'installed', 'updated', or 'unchanged'
	" - force:  set on PlugInstall! or PlugUpdate!
	if a:info.status == 'installed' || a:info.force
		!./install.py --clang-completer --tern-completer
	endif
endfunction

" Plug 'git@github.com:kana/vim-smartinput.git'
" Plug 'git@github.com:itchyny/calendar.vim.git'
" Plug 'git@github.com:vimwiki/vimwiki.git'
" Plug 'git@github.com:xolox/vim-notes.git'
Plug 'git@github.com:jpalardy/vim-slime.git'
" Plug 'git@github.com:xolox/vim-misc.git'
" Plug 'git@github.com:xolox/vim-session.git'
Plug 'git@github.com:Lokaltog/vim-easymotion.git'
Plug 'git@github.com:vim-scripts/fencview.vim.git'
Plug 'git@github.com:vim-scripts/camelcasemotion.git'
Plug 'git@github.com:mhinz/vim-hugefile.git'
Plug 'git@github.com:jiangmiao/auto-pairs.git'
Plug 'git@github.com:vim-scripts/matchit.zip.git'
Plug 'git@github.com:SirVer/ultisnips.git'
Plug 'git@github.com:mbbill/undotree.git'
Plug 'git@github.com:tpope/vim-fugitive.git'
Plug 'git@github.com:airblade/vim-gitgutter.git'
Plug 'git@github.com:vim-scripts/vim-svngutter'
Plug 'git@github.com:honza/vim-snippets.git'
Plug 'git@github.com:inkarkat/vim-ingo-library.git'
Plug 'git@github.com:kana/vim-textobj-user.git'
Plug 'git@github.com:maxbrunsfeld/vim-yankstack.git'
Plug 'git@github.com:kana/vim-textobj-indent.git'
Plug 'git@github.com:kana/vim-textobj-line.git'
Plug 'git@github.com:kana/vim-textobj-entire.git'
Plug 'git@github.com:sgur/vim-textobj-parameter.git'
Plug 'git@github.com:glts/vim-textobj-comment.git'
Plug 'git@github.com:Julian/vim-textobj-variable-segment.git'
Plug 'git@github.com:rizzatti/dash.vim.git'
Plug 'git@github.com:kien/ctrlp.vim.git'
Plug 'git@github.com:jlanzarotta/bufexplorer.git'
Plug 'git@github.com:scrooloose/nerdtree.git'
Plug 'git@github.com:Xuyuanp/nerdtree-git-plugin.git'
Plug 'git@github.com:mhinz/vim-startify.git'
Plug 'git@github.com:majutsushi/tagbar.git'
Plug 'git@github.com:terryma/vim-expand-region.git'
Plug 'git@github.com:terryma/vim-multiple-cursors.git'
Plug 'git@github.com:tpope/vim-commentary.git'
Plug 'git@github.com:tpope/vim-repeat.git'
Plug 'git@github.com:tpope/vim-surround.git'
Plug 'git@github.com:vim-scripts/AnsiEsc.vim.git'
Plug 'git@github.com:tpope/vim-unimpaired.git'
Plug 'git@github.com:mhinz/vim-grepper.git'
" Plug 'git@github.com:/usr/local/opt/fzf.git'
" Plug 'git@github.com:junegunn/fzf.vim.git'
Plug 'git@github.com:vim-scripts/WhereFrom.git'
Plug 'git@github.com:tpope/vim-dispatch.git'
Plug 'git@github.com:godlygeek/tabular.git'
Plug 'git@github.com:wellle/visual-split.vim.git'
Plug 'git@github.com:wellle/tmux-complete.vim.git'
Plug 'git@github.com:tpope/vim-vinegar.git'
Plug 'git@github.com:idanarye/vim-makecfg.git'

Plug 'git@github.com:w0rp/ale.git'
Plug 'git@github.com:Chiel92/vim-autoformat.git'
Plug 'git@github.com:metakirby5/codi.vim.git'


Plug 'git@github.com:jceb/vim-orgmode'
Plug 'git@github.com:tpope/vim-speeddating'


Plug 'git@github.com:Shougo/vimproc.vim.git', {'for': ['c', 'cpp', 'cmake', 'typescript'], 'do': 'make'}

Plug 'git@github.com:vim-scripts/CCTree.git', {'for':['c', 'cpp']}
Plug 'git@github.com:vim-scripts/a.vim.git', {'for': ['c', 'cpp']}
Plug 'git@github.com:richq/vim-cmake-completion.git', {'for': 'cmake'}
Plug 'git@github.com:vhdirk/vim-cmake.git', {'for': ['cmake', 'c', 'cpp']}
" Plug 'git@github.com:idanarye/vim-vebugger.git', {'for': ['cmake', 'c', 'cpp']}
" Plug 'git@github.com:libclang-vim/libclang-vim.git', {'do': './autogen.sh && make', 'for':['c', 'cpp']}

Plug 'git@github.com:bps/vim-textobj-python.git', {'for': 'python'}
Plug 'git@github.com:jmcantrell/vim-virtualenv.git', {'for': 'python'}

Plug 'git@github.com:alvan/vim-closetag.git', {'for': ['html', 'css', 'xhtml', 'xml']}
Plug 'git@github.com:mattn/emmet-vim.git', {'for': ['html', 'css', 'xhtml', 'xml']}
" Plug 'git@github.com:Valloric/MatchTagAlways.git', {'for': ['html', 'css', 'xhtml', 'xml']}
Plug 'git@github.com:gregsexton/MatchTag.git', {'for': ['html', 'css', 'xhtml', 'xml']}
Plug 'git@github.com:whatyouhide/vim-textobj-xmlattr.git', {'for': ['html', 'css', 'xhtml', 'xml']}

Plug 'git@github.com:rsmenon/vim-mathematica.git'

Plug 'git@github.com:suan/vim-instant-markdown.git', {'for': 'markdown'}
Plug 'git@github.com:plasticboy/vim-markdown.git', {'for': 'markdown'}

Plug 'git@github.com:guns/vim-clojure-static.git', {'for': 'clojure'}
Plug 'git@github.com:tpope/vim-fireplace.git', {'for': 'clojure'}
Plug 'git@github.com:raymond-w-ko/vim-niji.git', {'for': 'clojure'}

Plug 'git@github.com:derekwyatt/vim-scala.git', {'for': 'scala'}
Plug 'git@github.com:ktvoelker/sbt-vim.git', {'for': 'scala'}

Plug 'git@github.com:leafgarland/typescript-vim.git', {'for': 'typescript'}
Plug 'git@github.com:Quramy/tsuquyomi.git', {'for': 'typescript'}

Plug 'git@github.com:xolox/vim-lua-ftplugin.git', {'for': 'lua'}
Plug 'git@github.com:tbastos/vim-lua.git', {'for': 'lua'}
Plug 'git@github.com:vim-scripts/luarefvim.git', {'for': 'lua'}

Plug 'git@github.com:lervag/vimtex.git', {'for': ['tex', 'plaintex', 'bst']}
Plug 'git@github.com:rbonvall/vim-textobj-latex.git', {'for': ['tex', 'plaintex', 'bst']}

Plug 'git@github.com:Valloric/YouCompleteMe.git', { 'do': function('BuildYCM') , 'for': ['python','objc', 'c', 'cpp']}
Plug 'git@github.com:rdnetto/YCM-Generator.git', { 'branch': 'stable', 'for': ['python', 'c', 'cpp']}

Plug 'git@github.com:tenfyzhong/CompleteParameter.vim.git', {'for': ['python', 'c', 'cpp']}

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

syntax on
filetype on
" set foldmethod=indent
set encoding=utf-8
set termencoding=gbk
set fileencoding=utf-8
set fileencodings=ucs-bom,utf-8,cp936,gb18030,big5,euc-jp,euc-kr,latin1
set foldlevel=100
set scrolloff=0
set scs
hi normal guibg=#153948 guifg=white
set guifont=Monaco:h13
set number
set relativenumber
set ignorecase
set nosmartcase
set tag=./tags,tags,../tags,../../tags,../../../tags
set cst
runtime $VIMRUNTIME/macros/matchit.vim

"----------this is plugins's config-----------------------
"this is so strange, i need figure is out.
set dictionary-=/usr/share/dict/words dictionary+=/usr/share/dict/words

"let g:neocomplcache_enable_ignore_case = 1
nmap gs  <plug>(GrepperOperator)
xmap gs  <plug>(GrepperOperator)
nnoremap <leader>vr :Grepper<cr>
" nnoremap <leader>vv :Grepper -tool ag -cword -noprompt -query '--ignore-dir "build"'<CR>
nnoremap <leader>vv :Grepper -tool ag -cword -noprompt -query<CR>
let g:grepper = {'tools': ['ag'],
			\'ag': {
			\  'escape': '\^$.*+?()[]{}|',
			\  'grepformat': '%f:%l:%c:%m,%f:%l:%m',
			\  'grepprg': 'ag --vimgrep --ignore-dir "build"'
			\}}


"Tagbar's config
if !hasmapto(':TagbarToggle')
	map \tg :TagbarToggle<CR>
	map \ct :!ctags -R -f /Users/gfgkmn/OpenSource/tags
				\`python -c "from distutils.sysconfig
				\import get_python_lib; print get_python_lib()"`<CR>

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
	let g:tagbar_type_cmake = {
				\'cmaketype' : 'CMakeFile',
				\'kinds' : [
				\'v:var',
				\'f:func',
				\'m:macro',
				\'x:regex'
				\],
				\'sort': 1}
endif

if !hasmapto(':TagbarTogglePause')
	map \lt :TagbarTogglePause<CR>
	map \t2 :TagbarSetFoldlevel! 2<CR>
	map \t1 :TagbarSetFoldlevel! 1<CR>
endif
let g:tagbar_foldlevel = 2


"tex preview config
let g:tex_flavor                     = 'latex'
let g:tex_indent_items                    = 0
let g:Tex_DefaultTargetFormat        = 'pdf'
let g:Tex_CompileRule_pdf = 'pdflatex -src-specials -synctex=1 -interaction=nonstopmode $*'
let g:Tex_FormatDependency_pdf        = 'pdf'
let g:vimtex_view_method = 'general'
let g:vimtex_enabled = 1
let g:vimtex_complete_img_use_tail = 1
let g:vimtex_view_general_viewer = 'open'
let g:vimtex_view_general_options = '-r @line @pdf @tex'
let g:vimtex_compiler_latexmk = {'callback' : 0}

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

" close them all
map \ca :NERDTreeClose <bar> cclose <bar> pclose <bar> lclose <bar> nohl <bar> UndotreeHide <bar> TagbarClose<CR>
map \ci :only<CR>

" yankstack config
nmap <leader>p <Plug>yankstack_substitute_older_paste
nmap <leader>P <Plug>yankstack_substitute_newer_paste

" NerdTree's keymappint
if !hasmapto(':NERDTreeToggle')
	map \nt :NERDTreeToggle<CR>
	map \nr :NERDTreeFind<CR>
endif

" vim-instant-markdown config
let g:instant_markdown_allow_unsafe_content = 1
let g:instant_markdown_autostart = 0

" dash's keymapping
if !hasmapto(':DashSearch')
	nmap <silent> <leader>d <Plug>DashSearch
endif

"Gundo's keymapping
if !hasmapto(':UndotreeToggle')
	map \gt :UndotreeToggle<CR>
endif

"gitgutter refresh
map \tr :GitGutterAll<CR>

"""youCompleteMe's config
"" function! SetYoucomeplete()
let g:ycm_complete_in_comments = 1
let g:ycm_python_binary_path = "python"
let g:ycm_min_num_of_chars_for_completion = 56
let g:ycm_show_diagnostics_ui = 0
let g:ycm_key_invoke_completion = '<C-S-o>'
let g:ycm_confirm_extra_conf = 0
let g:ycm_key_list_select_completion = ['<tab>', '<Down>']
let g:ycm_key_list_previous_completion = ['<s-tab>', '<Up>']
let g:ycm_global_ycm_extra_conf = "~/.vim/vundles/YouCompleteMe/third_party/ycmd/cpp/ycm/.ycm_extra_conf.py"
nnoremap <leader>gf :YcmCompleter GoToDeclaration<CR>
nnoremap <leader>gg :YcmCompleter GoToDefinition<CR>
autocmd filetype cpp nnoremap <leader>gl :YcmCompleter GoToImprecise<CR>
autocmd filetype python nnoremap <leader>gr :YcmCompleter GoToReference<CR>
nnoremap <leader>gd :YcmCompleter GetDoc<CR>
autocmd filetype cpp nnoremap <leader>gc :YcmCompleter GetParent<CR>
autocmd filetype cpp nnoremap <leader>gp :YcmCompleter GetType<CR>

if !exists("g:ycm_semantic_triggers")
	" let g:ycm_semantic_triggers = {}
	let g:ycm_semantic_triggers =  {
				\   'c' : ['->', '.'],
				\   'objc' : ['->', '.', 're!\[[_a-zA-Z]+\w*\s', 're!^\s*[^\W\d]\w*\s',
				\             're!\[.*\]\s'],
				\   'ocaml' : ['.', '#'],
				\   'cpp,objcpp' : ['->', '.', '::'],
				\   'perl' : ['->'],
				\   'php' : ['->', '::'],
				\   'cs,java,javascript,typescript,d,python,perl6,scala,vb,elixir,go' : ['.'],
				\   'ruby' : ['.', '::'],
				\   'lua' : ['.', ':'],
				\   'erlang' : [':'],
				\   'typescript': ['.'],
				\   'tex': [
				\     're!\\[A-Za-z]*cite[A-Za-z]*(\[[^]]*\]){0,2}{[^}]*',
				\     're!\\[A-Za-z]*ref({[^}]*|range{([^,{}]*(}{)?))',
				\     're!\\hyperref\[[^]]*',
				\     're!\\includegraphics\*?(\[[^]]*\]){0,2}{[^}]*',
				\     're!\\(include(only)?|input){[^}]*',
				\     're!\\\a*(gls|Gls|GLS)(pl)?\a*(\s*\[[^]]*\]){0,2}\s*\{[^}]*',
				\     're!\\includepdf(\s*\[[^]]*\])?\s*\{[^}]*',
				\     're!\\includestandalone(\s*\[[^]]*\])?\s*\{[^}]*',
				\    ]
				\   }
endif
"" endfunction

" CompleteParameter config
inoremap <silent><expr> K complete_parameter#pre_complete("()")

"UltiSnips config
let g:UltiSnipsListSnippets = "<c-l>"
" Trigger configuration.
let g:UltiSnipsExpandTrigger="<c-j>"
"let g:UltiSnipsJumpForwardTrigger="<c-j>"
"let g:UltiSnipsJumpBackwardTrigger="<c-k>"
"let g:UltiSnipsSnippetsDir = ['UltiSnips', '~/.vim/UltiSnips/']
let g:UltiSnipsSnippetDirectories = ['UltiSnips', '~/.vim/UltiSnips/']

"vim-slime's config
let g:slime_target = 'tmux'
let g:slime_python_ipython = 1
let g:slime_default_config = {"socket_name": "default", "target_pane": ":"}
let g:slime_dont_ask_default = 1
noremap <leader>s :SlimeSend<CR>
noremap <leader>ss :%SlimeSend<CR>
noremap <leader>si dwlpldt)%p

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

" vedebugger leader
" let g:vebugger_leader=','

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
endfunction

nmap <Leader>f :call GotoJump()<CR>

" ale check key-binding
" let g:ale_sign_error = '?'
" let g:ale_sign_warning = '●'
let g:ale_enabled = 0
let g:ale_linters = {"python": ['flake8'], "sh": ['shellcheck']}
highlight clear AlEErrorSign
highlight clear AlEWarningSign
noremap <leader>ch :ALEToggle<CR>
noremap <leader>lo :lopen<CR>
noremap <leader>co :copen<CR>
noremap <leader>cq :cclose<CR>

" i don's which's this config
noremap <leader>ol :browse oldfiles<CR>
noremap ]d :tabnext<CR>
noremap <leader>oi :e ~/.vimrc<CR>
noremap <leader>rl :so ~/.vimrc<CR>
noremap ge :e <cfile><CR>

"codi config
noremap <leader>hc :Codi!! python<CR>

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
" map \a :e %:p:s,.h$,.X123X,:s,.m$,.h,:s,.X123X$,.m,<CR>

" set mathemaitca syntax on
au! BufRead,BufNewFile *.wls      set ft=mma sw=2
autocmd FileType mma setlocal commentstring=(*\ %s\ *)

"----------indent and fold config----------------------
set diffopt=filler,context:3
autocmd FileType python setlocal et sta sw=4 sts=4
autocmd FileType objc setlocal et sta sw=4 sts=4
autocmd FileType javascript setlocal et sta sw=4 sts=4
autocmd FileType cpp setlocal et sta sw=4 sts=4
autocmd FileType c setlocal et sta sw=4 sts=4
autocmd FileType java setlocal tabstop=4
" autocmd FileType cpp setlocal tabstop=4
" autocmd FileType python setlocal foldmethod=indent
set foldmethod=manual
" autocmd FileType c setlocal foldmethod=expr foldexpr=getline(v:lnum)=~'^\s*//'
" autocmd FileType python setlocal foldmethod=expr foldexpr=getline(v:lnum)=~'^\s*#'
command! -nargs=1 Silent execute 'silent !' . <q-args> | execute 'redraw!'
set matchpairs+=<:>
" avoid make message prompt
let g:bufferline_echo=0
set shortmess=at
" set complete-=i
" set foldlevel=99

autocmd FileType tex setlocal spell

"----------autoformat config-------------
noremap <leader>cf :Autoformat<CR>
" let g:formatter_yapf_style = 'pep8'
" consider use autoformat to replace all of them below
let g:formatdef_astyle_java = '"astyle --mode=java --style=google --max-code-length=95
		\ --indent-labels --indent-preproc-block --break-after-logical
		\ -pcH".(&expandtab ? "s".&shiftwidth : "t")'
let g:formatdef_google_java = "'java -jar ~/Applications/java_formatter.jar - 
			\--skip-removing-unused-imports --aosp --skip-sorting-imports 
			\--lines '.a:firstline.':'.a:lastline"
" let g:formatters_java = ['google_java', 'astyle_java']
let g:formatters_java = ['google_java']
let g:formatdef_clang_format = "'clang-format -style=\"{BasedOnStyle: Google, IndentWidth: 4, 
			\AlwaysBreakTemplateDeclarations: false, ColumnLimit: 95}\" 
			\-lines='.a:firstline.':'.a:lastline"
let g:formatters_cpp = ['clang_format']
let g:formatdef_my_cmake = '"cmake-format -"'
let g:formatters_cmake = ['my_cmake']
" let g:autoformat_verbosemode=1
autocmd FileType python noremap <leader>cf :call yapf#YAPF()<cr>
" autocmd FileType python call SetYoucomeplete()

" open file from anywhere config
" Search spotlight {{{2
command! -nargs=1 FzfSpotlight call fzf#run(fzf#wrap({
            \ 'source'  : 'mdfind -onlyin ~ <q-args>',
            \ 'options' : '-m --prompt "Spotlight> "'
            \ }))
nnoremap <leader>mf :FzfSpotlight 


"----------this is running file config-------------
function! GetErrorNum()
	let qflist = getqflist()
	let error_count = 0
	for i in qflist
		if i['valid'] == 1
			let error_count += 1
		endif
	endfor
	return error_count
endfunction


function! Generalmake()
	if filereadable("CMakelists.txt")
		if !isdirectory("build")
			call mkdir('build', 'p')
		endif
		" :!cd build && cmake ..
		:CMake
		:make
		" all your need is a redraw! to avoid status line prompt
		if GetErrorNum() > 0
			:redraw!
			:copen
		else
			:redraw!
			" :!$(gfind -maxdepth 2 -executable -type f -not -path '*/CMakeFiles/*')
		endif
	elseif filereadable("makefile")
		:make
		if GetErrorNum() > 0
			:redraw!
			:copen
		else
			:redraw!
			" :!$(gfind -maxdepth 2 -executable -type f -not -path '*/CMakeFiles/*')
		endif
		" all your need is a redraw! to avoid status line prompt
	else
		:e makefile
	endif
endfunction

function! SwitchOrCreate()
	if filereadable("makefile")
		:e makefile
	elseif filereadable("CMakelists.txt")
		:e CMakelists.txt
	else
		:e makefile
	endif
endfunction

nmap <leader>r :!%:p<CR>
autocmd FileType vim nmap <leader>r :!vim -i NONE -u NONE -U NONE -V1 -nNesS % -c 'qall'<CR>
autocmd FileType python nmap <leader>r :!python %<CR>
autocmd FileType lua nmap <leader>r :!th %<CR>
autocmd FileType markdown nmap <leader>r :InstantMarkdownPreview<CR>
autocmd FileType sh nmap <leader>r :!bash %<CR>
" autocmd FileType markdown let b:dispatch = 'octodown --live-reload %'
autocmd FileType cpp nmap <leader>a :A<CR>
autocmd FileType c nmap <leader>a :A<CR>

" autocmd FileType cpp nmap <leader>r :!$(gfind -maxdepth 3 -executable -type f -not -path '*/CMakeFiles/*')<CR>
autocmd FileType cpp nmap <leader>r :!g++ -std=c++11 % && $(gfind -maxdepth 3 -executable -type f -not -path '*/CMakeFiles/*')<CR>
" jump to the previous function
autocmd Filetype cpp nnoremap <silent> [m :call
			\ search('\(\(if\\|for\\|while\\|switch\\|catch\)\_s*\)\@64<!(\_[^)]*)\_[^;{}()]*\zs{', "bw")<CR>
autocmd Filetype cpp nnoremap <silent> ]m :call 
			\ search('\(\(if\\|for\\|while\\|switch\\|catch\)\_s*\)\@64<!(\_[^)]*)\_[^;{}()]*\zs{', "w")<CR>
nmap <leader>cr :CMakeClean<CR>
nmap <leader>mk :call Generalmake()<CR>
nmap <leader>mc :set filetype=cpp<CR>
nmap <leader>ml :call SwitchOrCreate()<CR>
nmap <leader>df :windo diffthis<CR>
nmap <leader>do :windo diffoff<CR>

function FloatUp()
    while line(".") > 1
                \ && (strlen(getline(".")) < col(".")
                \ || getline(".")[col(".") - 1] =~ '\s')
        norm k
    endwhile
endfunction

function FloatDown()
  while line(".") > 1 && (strlen(getline(".")) < col(".") || getline(".")[col(".") - 1] =~ '\s')
    norm j
  endwhile
endfunction

noremap <silent> [1 :call FloatUp()<CR>
noremap <silent> ]1 :call FloatDown()<CR>

" self defined function
function! s:get_visual_selection()
	" from http://stackoverflow.com/a/6271254/371334
	let [lnum1, col1] = getpos("'<")[1:2]
	let [lnum2, col2] = getpos("'>")[1:2]
	let lines = getline(lnum1, lnum2)
	let lines[-1] = lines[-1][: col2 - (&selection == 'inclusive' ? 1 : 2)]
	let lines[0] = lines[0][col1 - 1:]
	"return join(lines, "\n")
	return lines
endfunction

function! Mathpipe1()
	let mathpipe = s:get_visual_selection()
	call writefile(mathpipe, '/tmp/mathpipein')
	silent !cat /tmp/mathpipein | ~/Applications/bin/mathpipe.m
endfunction

function! Mathpipe2()
	let mathpipe = s:get_visual_selection()
	call writefile(mathpipe, '/tmp/mathpipein')
	silent !cat /tmp/mathpipein | ~/Applications/bin/mathpipe.m > /tmp/mathpipeout
	normal `>
	r /tmp/mathpipeout
endfunction

xnoremap <leader>m :<c-h><c-h><c-h><c-h><c-h>call Mathpipe2()<CR>
xnoremap <leader>M :<c-h><c-h><c-h><c-h><c-h>call Mathpipe1()<CR>
noremap ,cf :let @+=expand("%:p")<CR>
map ,cp :r!ssh sogou_dev "xclip -o"<CR>

vnoremap <leader>en :!python -c 'import sys,urllib;print urllib.quote(sys.stdin.read().strip())'<cr>
vnoremap <leader>de :!python -c 'import sys,urllib;print urllib.unquote(sys.stdin.read().strip())'<cr>
