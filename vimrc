" source $VIMRUNTIME/vimrc_example.vim
" source $VIMRUNTIME/mswin.vim
" behave mswin
set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath=&runtimepath

set nocompatible              " be iMproved, required
filetype off                  " required

"----------set the runtime path to include Vundle and initialize-------------------
set rtp+=~/.vim/vundles/vim-plug
" alternatively, pass a path where Vundle should install plugins
set backup
set undofile
set display=lastline
set showcmd
set backupdir=~/.vimbakfiles/
set undodir=~/.vimbakfiles/undofiles/
if has('mac')
    set termwinsize=15x0
    set splitbelow
endif
" set path+=/usr/local/Cellar/llvm/6.0.0/include/c++/v1
set exrc
set secure
" set macmeta
" autocmd BufEnter * lcd %:p:h
autocmd FocusGained * :redraw!
if has('mac')
    colorscheme gfgkmn
else
    colorscheme default
endif
if &diff
    colorscheme default
endif

" call vundle#begin("~/.vim/vundles")
call plug#begin('~/.vim/vundles')

" Python Setting {
if has("gui_macvim")
    set pythondll=/usr/local/Frameworks/Python.framework/Versions/3.6/Python
    set pythonhome=/usr/local/Frameworks/Python.framework/Versions/3.6
    set pythonthreedll=/usr/local/Frameworks/Python.framework/Versions/3.6/Python
    set pythonthreehome=/usr/local/Frameworks/Python.framework/Versions/3.6
endif
" }

if !has('nvim')
    source $VIMRUNTIME/defaults.vim
endif
if &t_Co > 2 || has("gui_running")
  " Switch on highlighting the last used search pattern.
  set hlsearch
endif

" dvc file syntax
autocmd! BufNewFile,BufRead Dvcfile,*.dvc setfiletype yaml
autocmd! BufNewFile,BufRead .tern-project setfiletype json
autocmd! BufNewFile,BufRead *.conf setfiletype configfile
autocmd! BufNewFile,BufRead *.coffee setfiletype coffeescript


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
        if has('mac')
            !./install.py --all
        else
            !./install.py --clang-completer
        endif
    endif
endfunction

function! TernInstall(info)
    " info is a dictionary with 3 fields
    " - name:   name of the plugin
    " - status: 'installed', 'updated', or 'unchanged'
    " - force:  set on PlugInstall! or PlugUpdate!
    if a:info.status == 'installed' || a:info.force
        !npm install
    endif
endfunction

" Plug 'xolox/vim-notes'
" Plug 'xolox/vim-misc'
" Plug 'xolox/vim-session'
" Plug 'skywind3000/asyncrun.vim'
Plug 'jpalardy/vim-slime'
Plug 'Lokaltog/vim-easymotion'
Plug 'vim-scripts/fencview.vim'
Plug 'vitalk/vim-shebang'
Plug 'vim-scripts/camelcasemotion'
Plug 'mhinz/vim-hugefile'
Plug 'jiangmiao/auto-pairs'
Plug 'dpelle/vim-LanguageTool'
Plug 'mbbill/undotree'
Plug 'tpope/vim-fugitive'
Plug 'junegunn/gv.vim'
Plug 'sodapopcan/vim-twiggy'
" Plug 'mhinz/vim-signify'
Plug 'airblade/vim-gitgutter'
Plug 'honza/vim-snippets'
Plug 'inkarkat/vim-ingo-library'
Plug 'kana/vim-textobj-user'
Plug 'maxbrunsfeld/vim-yankstack'
Plug 'kana/vim-textobj-indent'
Plug 'kana/vim-textobj-line'
Plug 'airblade/vim-rooter'
Plug 'kana/vim-textobj-entire'
Plug 'sgur/vim-textobj-parameter'
Plug 'glts/vim-textobj-comment'
if has('mac')
    Plug 'tpope/vim-dispatch'
    Plug 'mityu/vim-applescript'
endif
Plug 'Julian/vim-textobj-variable-segment'
Plug 'rizzatti/dash.vim'
Plug 'jlanzarotta/bufexplorer'
Plug 'mhinz/vim-startify'
Plug 'liuchengxu/vista.vim'
Plug 'terryma/vim-expand-region'
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-surround'
Plug 'vim-scripts/AnsiEsc.vim'
Plug 'kshenoy/vim-signature'
Plug 'tpope/vim-unimpaired'
Plug 'gfgkmn/web_search'
Plug 'mhinz/vim-grepper'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'vim-scripts/WhereFrom'
Plug 'godlygeek/tabular'
Plug 'wellle/visual-split.vim'
Plug 'wellle/tmux-complete.vim'
Plug 'tpope/vim-vinegar'
Plug 'idanarye/vim-makecfg'
Plug 'tfnico/vim-gradle'
Plug 'machakann/vim-swap'
Plug 'zenbro/mirror.vim'

Plug 'w0rp/ale'
Plug 'Chiel92/vim-autoformat'
Plug 'metakirby5/codi.vim'
Plug 'johngrib/vim-mac-dictionary'
if v:version >= 801
    " Plugin goes here.
    Plug 'mg979/vim-visual-multi'
    Plug 'vim-scripts/VimRepress'
    Plug 'SirVer/ultisnips'
    Plug 'kentaroi/ultisnips-swift'
endif
Plug 'jceb/vim-orgmode'
Plug 'tpope/vim-speeddating'

Plug 'Shougo/vimproc.vim', {'for': ['c', 'cpp', 'cmake', 'typescript'], 'do': 'make'}

if has('linux')
    Plug 'scrooloose/nerdtree'
    Plug 'Xuyuanp/nerdtree-git-plugin'
elseif has('nvim')
    Plug 'Shougo/defx.nvim', { 'do': ':UpdateRemotePlugins' }
else
    Plug 'kristijanhusak/defx-git'
    Plug 'Shougo/defx.nvim'
    Plug 'roxma/nvim-yarp'
    Plug 'roxma/vim-hug-neovim-rpc'
endif

Plug 'vim-scripts/CCTree', {'for':['c', 'cpp']}
Plug 'vim-scripts/a.vim', {'for': ['c', 'cpp']}
Plug 'richq/vim-cmake-completion', {'for': 'cmake'}
" Plug 'vhdirk/vim-cmake', {'for': ['cmake', 'c', 'cpp']}
Plug 'cdelledonne/vim-cmake', {'for': ['cmake', 'c', 'cpp']}
" Plug 'idanarye/vim-vebugger', {'for': ['cmake', 'c', 'cpp']}
" Plug 'libclang-vim/libclang-vim', {'do': './autogen.sh && make', 'for':['c', 'cpp']}

Plug 'bps/vim-textobj-python', {'for': 'python'}
Plug 'jmcantrell/vim-virtualenv', {'for': 'python'}

Plug 'alvan/vim-closetag', {'for': ['html', 'css', 'xhtml', 'xml']}
Plug 'mattn/emmet-vim', {'for': ['html', 'css', 'xhtml', 'xml', 'mason']}
Plug 'whatyouhide/vim-textobj-xmlattr', {'for': ['html', 'css', 'xhtml', 'xml']}

Plug 'rsmenon/vim-mathematica'

Plug 'jalvesaq/Nvim-R', {'for': ['R']}

Plug 'Rykka/riv.vim', {'for': 'rst'}

Plug 'plasticboy/vim-markdown', {'for': 'markdown'}
Plug 'iamcco/markdown-preview.nvim', {'for': 'markdown', 'do': 'cd app & yarn install'}

Plug 'guns/vim-clojure-static', {'for': 'clojure'}
Plug 'tpope/vim-fireplace', {'for': 'clojure'}
Plug 'raymond-w-ko/vim-niji', {'for': 'clojure'}

Plug 'derekwyatt/vim-scala', {'for': 'scala'}
Plug 'ktvoelker/sbt-vim', {'for': 'scala'}

Plug 'kchmck/vim-coffee-script', {'for': 'coffeescript'}

Plug 'Shougo/unite.vim', {'for': ['typescript', 'javascript']}
Plug 'leafgarland/typescript-vim', {'for': ['typescript', 'javascript']}
Plug 'Quramy/tsuquyomi', {'for': ['typescript', 'javascript']}
Plug 'mhartington/vim-typings', {'for': ['typescript', 'javascript']}

Plug 'xolox/vim-lua-ftplugin', {'for': 'lua'}
Plug 'tbastos/vim-lua', {'for': 'lua'}
Plug 'vim-scripts/luarefvim', {'for': 'lua'}

Plug 'lervag/vimtex', {'for': ['tex', 'plaintex', 'bst']}
Plug 'rbonvall/vim-textobj-latex', {'for': ['tex', 'plaintex', 'bst']}

Plug 'Valloric/YouCompleteMe', { 'do': function('BuildYCM') , 'for': ['python','objc', 'c', 'cpp', 'java', 'javascript']}
Plug 'rdnetto/YCM-Generator', { 'branch': 'stable' }

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
set termencoding=utf-8
set fileencoding=utf-8
set fileencodings=ucs-bom,utf-8,cp936,gb18030,big5,euc-jp,euc-kr,latin1
set foldlevel=100
set scrolloff=0
set scs
hi normal guibg=#153948 guifg=white
if has('mac')
    set guifont=Monaco:h13
endif
set number
set relativenumber
set ignorecase
set nosmartcase
set tag=./tags,tags,../tags,../../tags,../../../tags,~/Applications/tags
set cst
runtime $VIMRUNTIME/macros/matchit.vim

"----------this is plugins's config-----------------------
"this is so strange, i need figure is out.
set dictionary-=/usr/share/dict/words dictionary+=/usr/share/dict/words

"let g:neocomplcache_enable_ignore_case = 1
" nmap gs  <plug>(GrepperOperator)
" xmap gs  <plug>(GrepperOperator)
nnoremap <leader>vr :Grepper<cr>
" nnoremap <leader>vv :Grepper -tool ag -cword -noprompt -query '--ignore-dir "build"'<CR>
nnoremap <leader>vv :Grepper -tool ag -cword -noprompt -query<CR>
let g:grepper = {'tools': ['ag'],
            \'ag': {
            \  'escape': '\^$.*+?()[]{}|',
            \  'grepformat': '%f:%l:%c:%m,%f:%l:%m',
            \  'grepprg': 'ag --vimgrep --ignore-dir "build"'
            \}}

" vim-swap 
" let g:swap#rules = deepcopy(g:swap#default_rules)
" todo to know how to sway a + b + c

" vim-rooter config
let g:rooter_patterns = ['.git', 'Makefile', 'CMakeLists.txt', '*.sln', 'build/env.sh', 'start.sh']
let g:rooter_silent_chdir = 1

" vista config
let g:vista#executive#ctags#support_json_format = 1
let g:vista#executives = ['coc', 'ctags', 'lcn', 'vim_lsp']
let g:vista#render#ctags = 'default'
let g:vista#renderer#ctags = 'default'
let g:vista#renderer#default#vlnum_offset = 3
let g:vista_icon_indent = ["▸ ", ""]
" let g:vista#renderer#enable_icon = 1
let g:vista_sidebar_width = 70
let g:vista#renderer#icons = {
\   "function": "•",
\   "variable": "◼︎",
\   "command": "►",
\   "map": "◆",
\   "class": "✦",
\   "member": "⦿",
\   "namespace": "❥",
\   "method": "✺",
\   "struct": "▲"
\  }
map \tg :Vista!!<CR>


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

function! HideOrPass()
    if winnr() > 1
        hide
    endif
    if bufwinnr('defx') > 0
        execute "bdelete " . bufnr('defx')
    endif
    if exists('t:twiggy_bufnr')
        :Twiggy
    endif
endfunction

" close them all
if has('mac')
    map <leader>ca :cclose <bar> pclose <bar> lclose <bar> nohl <bar> UndotreeHide <bar> Vista! <bar> :call HideOrPass()<CR>
else
    map <leader>ca :NERDTreeClose <bar> cclose <bar> pclose <bar> lclose <bar> nohl <bar> UndotreeHide <bar> Vista!<CR>
endif

map <leader>ci :only<CR>

" yankstack config
nmap <leader>p <Plug>yankstack_substitute_older_paste
nmap <leader>P <Plug>yankstack_substitute_newer_paste
set pastetoggle=<F2>

if has('linux')
    if !hasmapto(':NERDTreeToggle')
        map \nt :NERDTreeToggle<CR>
        map \nr :NERDTreeFind<CR>
    endif
    let g:NERDTreeSortOrder = ['\/$', '*','\.swp$',  '\.bak$', '\~$', '[[-timestamp]]']
else
    call defx#custom#option('_', {
                \ 'columns': 'indent:git:icons:filename',
                \ 'winwidth': 40,
                \ 'split': 'vertical',
                \ 'direction': 'topleft',
                \ 'show_ignored_files': 0,
                \ 'listed': 1,
                \ 'buffer_name': 'NERD_tree_1',
                \ 'root_marker': '▶︎ ',
                \ 'toggle': 1,
                \ 'resume': 1,
                \ 'ignored_files':
                \     '.mypy_cache,.pytest_cache,.git,.hg,.svn,.stversions'
                \   . ',__pycache__,.sass-cache,*.egg-info,.DS_Store,*.pyc,*.swp'
                \ })
     

    map <silent> <leader>nt :Defx<CR>
    nnoremap <silent> <Leader>nr :Defx `expand('%:p:h')` -search=`expand('%:p')`<CR>
    " Avoid the white space highting issue
    autocmd FileType defx match ExtraWhitespace /^^/
    " Keymap in defx
    autocmd FileType defx call s:defx_my_settings()

    function! s:defx_my_settings() abort
      IndentLinesDisable
      setl nospell
      setl signcolumn=no
      setl nonumber
      nnoremap <silent><buffer><expr> <CR> defx#is_directory() ? defx#do_action('open_or_close_tree') : defx#do_action('drop',)
      nnoremap <silent><buffer><expr> s defx#do_action('drop', 'split')
      nnoremap <silent><buffer><expr> v defx#do_action('drop', 'vsplit')
      nnoremap <silent><buffer><expr> t defx#do_action('drop', 'tabe')
      nnoremap <silent><buffer><expr> o defx#do_action('open_tree')
      nnoremap <silent><buffer><expr> O defx#do_action('open_tree_recursive')
      nnoremap <silent><buffer><expr> C defx#do_action('copy')
      nnoremap <silent><buffer><expr> P defx#do_action('paste')
      nnoremap <silent><buffer><expr> M defx#do_action('rename')
      if has('mac')
          nnoremap <silent><buffer><expr> D defx#do_action('remove_trash', 'force')
      else
          nnoremap <silent><buffer><expr> D defx#do_action('remove_trash')
      endif
      nnoremap <silent><buffer><expr> A defx#do_action('new_multiple_files')
      nnoremap <silent><buffer><expr> - defx#do_action('cd', ['..'])
      nnoremap <silent><buffer><expr> . defx#do_action('toggle_ignored_files')
      nnoremap <silent><buffer><expr> <Space> defx#do_action('toggle_select')
      nnoremap <silent><buffer><expr> R defx#do_action('redraw')
    endfunction

    " Defx git
    let g:defx_git#indicators = { 'Modified'  : '✹', 'Staged'    : '✚',
                \ 'Untracked' : '✭', 'Renamed'   : '➜',
                \ 'Unmerged'  : '═', 'Ignored'   : '☒',
                \ 'Deleted'   : '✖', 'Unknown'   : '?' }
    let g:defx_git#column_length = 0
    hi def link Defx_filename_directory NERDTreeDirSlash
    hi def link Defx_git_Modified Special
    hi def link Defx_git_Staged Function
    hi def link Defx_git_Renamed Title
    hi def link Defx_git_Unmerged Label
    hi def link Defx_git_Untracked Tag
    hi def link Defx_git_Ignored Comment

    " Defx icons
    " Requires nerd-font, install at https://github.com/ryanoasis/nerd-fonts or
    " brew cask install font-hack-nerd-font
    " Then set non-ascii font to Driod sans mono for powerline in iTerm2
    Plug 'kristijanhusak/defx-icons'
    " disbale syntax highlighting to prevent performence issue
    let g:defx_icons_enable_syntax_highlight = 1
endif

" Twiggy's config
if !hasmapto(':Twiggy')
    map \gm :Twiggy<CR>
endif


" dash's keymapping
if !hasmapto(':DashSearch')
    nmap <silent> <leader>dd <Plug>DashSearch
endif

" websearch
let g:web_search_use_default_mapping = "yes"
let g:web_search_engine = "google"
let g:web_search_command = "open"
noremap <leader>se :WebSearchVisual<CR>
nnoremap <leader>so :WebSearch 

" dict's keymapping
nnoremap <leader>ds :MacDictWord<CR>
nnoremap <leader>dr :MacDictQuery<CR>
" shows the raw string from the dictionary
" let g:vim_mac_dictionary_use_format = 0
if has('mac')
    let g:vim_mac_dictionary_use_app = 1
endif

"Gundo's keymapping
if !hasmapto(':UndotreeToggle')
    map \gt :UndotreeToggle<CR>
endif

""signify config
"let g:signify_vcs_list = ['hg', 'cvs', 'rcs', 'svn']
"highlight SignColumn ctermbg=NONE cterm=NONE guibg=NONE gui=NONE
"" highlight lines in Sy and vimdiff etc.)
"" highlight DiffAdd           cterm=bold ctermbg=none ctermfg=119
"" highlight DiffDelete        cterm=bold ctermbg=none ctermfg=167
"" highlight DiffChange        cterm=bold ctermbg=none ctermfg=227
"" highlight signs in Sy
"highlight SignifySignAdd    cterm=bold ctermbg=none  ctermfg=119
"highlight SignifySignDelete cterm=bold ctermbg=none  ctermfg=167
"highlight SignifySignChange cterm=bold ctermbg=none  ctermfg=227
"nnoremap <leader>hu :SignifyHunkUndo<CR>
"nnoremap <leader>hr :SignifyRefresh<CR>
"nnoremap <leader>hs :Gwrite<CR>
set updatetime=200

"gitgutter refresh
map \tr :GitGutterAll<CR>
map \ga :GitGutterToggle<CR>
let g:gitgutter_enabled = 1
let g:gitgutter_max_signs = 2000
" let g:gitgutter_map_keys = 0
let g:gitgutter_override_sign_column_highlight = 0
highlight clear SignColumn
highlight GitGutterAdd ctermfg=2
highlight GitGutterChange ctermfg=3
highlight GitGutterDelete ctermfg=1
highlight GitGutterChangeDelete ctermfg=4

" autopair config
" disable autpopair
" imap <C-d>p <M-p>
imap <C-d>u <M-p>
" bring next word forward
" imap <C-d>e <M-e>
imap <C-d>i <M-e>
" jump after paird symbol
" imap <C-d>n <M-n>
imap <C-d>o <M-n>
" after ignore input, regret it
" imap <C-d>b <M-b>
imap <C-d>p <M-b>

"""youCompleteMe's config
let g:ycm_complete_in_comments = 1
" let g:ycm_python_binary_path = "python"
let g:ycm_auto_trigger = 0
let g:ycm_auto_hover = ''
" let g:ycm_python_binary_path = "~/.virtualenvs/py3-dev/bin/python"
let g:ycm_min_num_of_chars_for_completion = 56
let g:ycm_show_diagnostics_ui = 0
" let g:ycm_key_invoke_completion = '<C-S-o>'
let g:ycm_confirm_extra_conf = 0
let g:ycm_key_list_select_completion = ['<tab>', '<Down>']
let g:ycm_key_list_previous_completion = ['<s-tab>', '<Up>']
let g:ycm_global_ycm_extra_conf = "~/.vim/vundles/YouCompleteMe/third_party/ycmd/cpp/ycm/.ycm_extra_conf.py"
" let g:ycm_global_ycm_extra_conf = "/Users/gfgkmn/Research/transformer/jungnet/.ycm_extra_conf.py"

function! GetYcmDebugFile()
    redir =>output
    silent YcmDebugInfo
    redir END
    let line = split(output, "\n")[-1][4:]
    silent execute "!ycmdebug ".line
    redraw!
endfunction 

nnoremap <leader>gg :YcmCompleter GoToDeclaration<CR>
nnoremap <leader>gf :YcmCompleter GoToDefinition<CR>
nnoremap <leader>gl :YcmCompleter GoToImprecise<CR>
nnoremap <leader>gr :YcmCompleter GoToReference<CR>
nnoremap <leader>gi :YcmCompleter GoToInclude<CR>
nnoremap <leader>gi :YcmCompleter GoToInclude<CR>
nnoremap <leader>gd :YcmCompleter GetDoc<CR>
nnoremap <leader>gc :YcmCompleter GetParent<CR>
nnoremap <leader>gp :YcmCompleter GetType<CR>
nnoremap <leader>yd :call GetYcmDebugFile()<CR>

inoremap <C-S-o> <C-x><C-o>

" Kite deep learning complete
" let g:kite_auto_complete=1
" let g:kite_tab_complete=1
" set completeopt-=menu
" set completeopt+=menuone   " Show the completions UI even with only 1 item
" set completeopt-=longest   " Don't insert the longest common text
" set completeopt-=preview   " Hide the documentation preview window
" set completeopt+=noinsert  " Don't insert text automatically
" set completeopt-=noselect  " Highlight the first completion automatically
" set completeopt=menuone,noinsert
" set statusline=%<%f\ %h%m%r%{kite#statusline()}%=%-14.(%l,%c%V%)\ %P
" set laststatus=2

"mirrorconfig
let g:mirror#spawn_command = ':Start '
nmap <leader>pu :MirrorPull<CR>
nmap <leader>ph :MirrorPush<CR>
nmap <leader>md :MirrorDiff<CR>



if !exists("g:ycm_semantic_triggers")
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

"UltiSnips config
let g:UltiSnipsUsePythonVersion = 3
let g:UltiSnipsListSnippets = "<c-l>"
let g:UltiSnipsExpandTrigger="<c-j>"
"let g:UltiSnipsJumpForwardTrigger="<c-j>"
"let g:UltiSnipsJumpBackwardTrigger="<c-k>"
let g:UltiSnipsSnippetDirectories=['~/.vim/UltiSnips/', 'UltiSnips']

"languagetools config
let g:languagetool_jar='~/Applications/LanguageTools/languagetool-commandline.jar'
set spelllang=en_us
map \cs :LanguageToolClear<CR>


"vim-slime's config
let g:slime_target = 'tmux'
let g:slime_python_ipython = 1
let g:slime_default_config = {"socket_name": "default", "target_pane": ":"}
let g:slime_dont_ask_default = 1
noremap <leader>ss :SlimeSend<CR>
noremap <leader>sa :%SlimeSend<CR>

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
        let pattern = '\v\c^\j'
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
let g:ale_sign_error = '✗'
let g:ale_sign_warning = '●'
let g:ale_enabled = 0
let g:ale_linters = {"python": ['flake8'], "sh": ['shellcheck'], "javascript": ["jslint"]}
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
noremap <leader>er :so ~/.vimrc<CR>
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
au! BufRead,BufNewFile *.wls setlocal ft=mma sw=2
autocmd FileType mma setlocal commentstring=(*\ %s\ *)

"----------indent and fold config----------------------
set diffopt=filler,context:3,iwhite
set et sw=4 sts=4 tabstop=4
if has('mac')
    autocmd FileType python setlocal textwidth=80
else
    autocmd FileType python setlocal textwidth=110
endif

" autocmd FileType cpp setlocal tabstop=4
" autocmd FileType python setlocal foldmethod=indent
set foldmethod=manual
" autocmd FileType c setlocal foldmethod=expr foldexpr=getline(v:lnum)=~'^\s*//'
" autocmd FileType python setlocal foldmethod=expr foldexpr=getline(v:lnum)=~'^\s*#'
set matchpairs+=<:>
" avoid make message prompt
let g:bufferline_echo=0
set shortmess=at
" set complete-=i
" set foldlevel=99

autocmd FileType tex setlocal spell
autocmd FileType tex setlocal complete-=i
autocmd FileType tex noremap <leader>wc :w !detex % \| wc<CR>

autocmd FileType lisp setlocal commentstring=;;%s


"----------autoformat config-------------
noremap <leader>cf :Autoformat<CR>
let g:formatters_java = ['astyle_java']
let g:formatdef_astyle_java = '"astyle --mode=java --style=google --max-code-length=".(&textwidth).
            \ "--indent-labels --indent-preproc-block --break-after-logical
            \ -pcH".(&expandtab ? "s".&shiftwidth : "t")'
" let g:formatters_java = ['google_java']
" let g:formatdef_google_java = "'java -jar ~/Applications/java_formatter.jar -
"             \--skip-removing-unused-imports --aosp --skip-sorting-imports
"             \--lines '.a:firstline.':'.a:lastline"
let g:formatters_cpp = ['clang_format']
let g:formatdef_clang_format = "'clang-format -style=\"{BasedOnStyle: Google, IndentWidth: 4,
            \AlwaysBreakTemplateDeclarations: false, ColumnLimit: ".(&textwidth)."}\"
            \ -lines='.a:firstline.':'.a:lastline"
let g:formatters_cmake = ['my_cmake']
let g:formatdef_my_cmake = '"cmake-format -"'
let g:formatters_mason = ['html_beautify']
let g:formatters_python = ['yapf']
let g:formatters_html = ['html_beautify']
let g:formatdef_html_beautify = '"html-beautify -".(&expandtab ? "s ".shiftwidth() :
            \"t").(&textwidth ? " -w ".&textwidth : "")'
let g:formatters_javascript= ['jsbeautify_javascript']
let g:formatdef_jsbeautify_javascript = '"js-beautify -".(&expandtab ? "s ".shiftwidth() :
            \"t").(&textwidth ? " -w ".&textwidth : "")'
" let g:formatter_yapf_style = 'google'
let g:formatdef_yapf = '"yapf --style=\"{column_limit: ".(&textwidth)."}\" -l ".a:firstline."-".a:lastline' 
let g:formatters_swift = ['swiftformat']
let g:formatdef_swiftformat = '"cat - | swiftformat --swiftversion 5.3.2 --quiet --linerange ".a:firstline.",".a:lastline'
let g:autoformat_autoindent = 0
let g:autoformat_retab = 0
let g:autoformat_remove_trailing_spaces = 0
" tocreate: write a function to print normal debug info, include ycmdebug,
" autoformat verbose, and ale linter etc
let g:autoformat_verbosemode=1
" 0 no message, 1 only error message, 2 all message
" let verbose=1

" open file from anywhere config
"
if has('popupwin') 
    let g:fzf_layout = { 'window': { 'width': 1, 'height': 1} }
else
    let g:fzf_layout = {'down': '30%'}
endif
if has('mac')
    command! -nargs=1 FzfSpotlight call fzf#run(fzf#wrap({
                \ 'source'  : 'mdfind -onlyin ~ <q-args>',
                \ 'options' : '-m --prompt "Spotlight> "'
                \ }))
else
    command! -nargs=1 FzfSpotlight call fzf#run(fzf#wrap({
                \ 'source'  : 'locate <q-args>',
                \ 'options' : '-m --prompt "Spotlight> "'
                \ }))
endif
nnoremap <leader>mf :FzfSpotlight<Space>
nnoremap <c-p> :Files<CR>
noremap <leader>v :History<CR>

" need to improve it
" function! ReformatMultiLines()
"     let brx = '^\s*"'
"     let erx = '"\s*$'
"     let fullrx = brx . '\(.\+\)' . erx
"     let startLine = line(".")
"     let endLine   = line(".")
"     while getline(startLine) =~ fullrx
"         let startLine -= 1
"     endwhile
"     if getline(endLine) =~ erx
"         let endLine += 1
"     endif
"     while getline(endLine) =~ fullrx
"         let endLine += 1
"     endwhile
"     if startLine != endLine
"         exec endLine . ' s/' . brx . '//'
"         exec startLine . ' s/' . erx . '//'
"         exec startLine . ',' . endLine . ' s/' . fullrx . '/\1/'
"         exec startLine . ',' . endLine . ' join'
"     endif
"     exec startLine
"     let orig_tw = &tw
"     if &tw == 0
"         let &tw = &columns
"         if &tw > 79
"             let &tw = 79
"         endif
"     endif
"     let &tw -= 3 " Adjust for missing quotes and space characters
"     exec "normal A%-%\<Esc>gqq"
"     let &tw = orig_tw
"     let endLine = search("%-%$")
"     exec endLine . ' s/%-%$//'
"     if startLine == endLine
"         return
"     endif
"     exec endLine
"     exec 'normal I"'
"     exec startLine
"     exec 'normal A "'
"     if endLine - startLine == 1
"         return
"     endif
"     let startLine += 1
"     while startLine != endLine
"         exec startLine
"         exec 'normal I"'
"         exec 'normal A "'
"         let startLine += 1
"     endwhile
" endfunction

function! s:copy_results(lines)
    let joined_lines = join(a:lines, "\n")
    if len(a:lines) > 1
        let joined_lines .= "\n"
    endif
    let @+ = joined_lines
endfunction
let g:fzf_action = {
            \ 'ctrl-t': 'tab split',
            \ 'ctrl-x': 'split',
            \ 'ctrl-v': 'vsplit',
            \ 'ctrl-y': function('s:copy_results'),
            \ }"

" vim-markdown config
let g:tex_conceal = ""
let g:vim_markdown_math = 1
if has('mac'):
    let g:mkdp_markdown_css = '/Users/gfgkmn/Configs/markdown_css/gfgkmn.css' 
endif


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
    let l:make2command = {'cmakelists.txt': ":CMakeGenerate! && :make", "makefile":":make",
                \ "build.gradle":":make", "build.sh":":!bash build.sh"}
    if index(['cpp', 'c', 'make', 'cmake'], &filetype) > -1
        let l:makefiles = ['CMakelists.txt', 'CMakeLists.txt', 'cmakelists.txt', 'makefile', 'MakeFile']
    elseif index(['java', 'groovy'], &filetype) > -1
        let l:makefiles = ['build.gradle', 'build.sh']
    elseif index(['javascript'], &filetype) > -1
        let l:makefiles = ['.tern-project']
    else
        let l:makefiles = ['build.sh']
    endif

    let l:nomkfile = 1
    let l:defaultmk = 'temp'
    for l:mkfile in l:makefiles
        if filereadable(l:mkfile)
            let l:nomkfile = 0
            execute l:make2command[tolower(l:mkfile)]
            if GetErrorNum() > 0
                :redraw!
                :copen
            else
                :redraw!
                " :!$(gfind -maxdepth 2 -executable -type f -not -path '*/CMakeFiles/*')
            endif
            break
        else
            let l:defaultmk = l:mkfile
        endif
    endfor

    if l:nomkfile
        :execute 'edit' l:defaultmk
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

function! HtmlPreview()
    silent execute "!nohup autoreload-server -w ./ --port 8000 &"
    silent execute "!open 'http://localhost:8000/".shellescape(expand('%'))."\'"
    redraw!
endfunction

function! Type2Js()
    silent execute "!tsc %"
    execute "!node %:r".".js"
    silent execute "!rm %:r".".js"
    redraw!
endfunction


nmap <leader>r :!%:p<CR>
autocmd BufEnter *.vim nmap <leader>r :!vim -i NONE -u NONE -U NONE -V1 -nNesS % -c 'qall'<CR>
autocmd BufEnter *.py nmap <leader>r :term python %<CR>
autocmd BufEnter *.py nmap <leader>tt :!python -m doctest -v %<CR>
autocmd BufEnter *.py nmap <leader>ut :!python -m unittest -v %<CR>
autocmd FileType lua nmap <leader>r :!th %<CR>
autocmd BufEnter *.md nmap <leader>r <Plug>MarkdownPreviewToggle
autocmd BufEnter *.ts nmap <leader>r :call Type2Js()<CR>
autocmd BufEnter *.rst nmap <leader>r :Riv2HtmlAndBrowse<CR>
autocmd BufEnter *.html nmap <leader>r :call HtmlPreview()<CR>
autocmd BufEnter *.sh nmap <leader>r :!bash %<CR>
autocmd FileType java nmap <leader>r :!javac % && java %:t:r<CR>
autocmd FileType mma nmap <leader>r :!wolframscript -script %<CR>
autocmd FileType groovy compiler gradle
autocmd FileType java compiler gradle
autocmd FileType cpp nmap <leader>a :A<CR>
autocmd FileType c nmap <leader>a :A<CR>

nnoremap <leader>gv :vertical rightbelow wincmd f<CR>

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

function! FloatUp()
    while line(".") > 1
                \ && (strlen(getline(".")) < col(".")
                \ || getline(".")[col(".") - 1] =~ '\s')
        norm k
    endwhile
endfunction

function! FloatDown()
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

function! Capatalize()
    let a:pos = getpos(".")
    normal eb~
    call setpos(".", a:pos)
endfunction
noremap <leader>tc :call Capatalize()<CR>

xnoremap <leader>m :<c-h><c-h><c-h><c-h><c-h>call Mathpipe2()<CR>
xnoremap <leader>M :<c-h><c-h><c-h><c-h><c-h>call Mathpipe1()<CR>
noremap ,cf :let @+=expand("%:p")<CR>
map ,cy :w !pbcopy<CR>

vnoremap <leader>en :!python -c 'import sys,urllib;print urllib.quote(sys.stdin.read().strip())'<cr>
vnoremap <leader>de :!python -c 'import sys,urllib;print urllib.unquote(sys.stdin.read().strip())'<cr>


" star search
if exists('loaded_starsearch')
	finish
endif
let loaded_starsearch = 1

let s:savedCpo = &cpo
set cpo&vim

function! s:VStarsearch_searchCWord()
	let wordStr = expand("<cword>")
	if strlen(wordStr) == 0
		echohl ErrorMsg
		echo 'E348: No string under cursor'
		echohl NONE
		return
	endif
	
	if wordStr[0] =~ '\<'
		let @/ = '\<' . wordStr . '\>'
	else
		let @/ = wordStr
	endif

	let savedUnnamed = @"
	let savedS = @s
	normal! "syiw
	if wordStr != @s
		normal! w
	endif
	let @s = savedS
	let @" = savedUnnamed
endfunction

" https://github.com/bronson/vim-visual-star-search/
function! s:VStarsearch_searchVWord()
	let savedUnnamed = @"
	let savedS = @s
	normal! gv"sy
	let @/ = '\V' . substitute(escape(@s, '\'), '\n', '\\n', 'g')
	let @s = savedS
	let @" = savedUnnamed
endfunction

nnoremap <silent> * :call <SID>VStarsearch_searchCWord()<CR>:set hls<CR>
vnoremap <silent> * :<C-u>call <SID>VStarsearch_searchVWord()<CR>:set hls<CR>

let &cpo = s:savedCpo
