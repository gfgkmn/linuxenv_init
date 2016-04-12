sudo usermod -s /bin/zsh $USER
mkdir .vimbakfiles
mkdir -p .vim/vundles/
cd .vim/vundles
git clone https://github.com/VundleVim/Vundle.vim.git
vim -c 'PluginUpdate' -c qa
