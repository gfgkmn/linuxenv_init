mkdir .vimbakfiles
mkdir -p .vim/vundles/
cd .vim/vundles
git clone https://github.com/VundleVim/Vundle.vim.git
vim -c 'PluginList' -c qa
