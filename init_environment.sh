sudo usermod -s /bin/zsh $USER
mkdir ~/.vimbakfiles
mkdir -p ~/.vim/vundles/
mkdir -p ~/Application/bin
git clone https://github.com/facebook/PathPicker.git
mv PathPicker ~/Application
ln -s ~/Application/PathPicker/fpp ~/Application/bin/fpp
cp ./j ~/Application/bin
cp ./z.sh ~/Application/bin
cd ~/.vim/vundles
git clone https://github.com/VundleVim/Vundle.vim.git
vim -c 'PluginUpdate' -c qa
