sudo usermod -s /bin/zsh $USER
mkdir ~/.vimbakfiles
mkdir -p ~/.vim/vundles/
mkdir -p ~/Application/bin
cp ./j ~/Application/bin
cp ./z.sh ~/Application/bin
cd ~/.vim/vundles
git clone https://github.com/VundleVim/Vundle.vim.git
vim -c 'PluginUpdate' -c qa
