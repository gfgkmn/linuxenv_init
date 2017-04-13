# sudo apt-get install ctags
mkdir ~/.vimbakfiles
mkdir -p ~/.vim/vundles/
mkdir -p ~/Application/bin
git clone https://github.com/facebook/PathPicker.git
mv PathPicker ~/Application
ln -s ~/Application/PathPicker/fpp ~/Application/bin/fpp
mkdir -p ~/.ipython/profile_default
cp ipython_config.py ~/.ipython/profile_default
cp ./.inputrc ~/
cp ./z.sh ~/Application/bin
current_folder=$(pwd)
cd ~/.vim/vundles
git clone https://github.com/junegunn/vim-plug.git
cd $current_folder
cp .vimrc ~/
cp ~/.vim/vundles/vim-plug/plug.vim ~/.vim/autoload/
vim -c 'PlugUpdate' -c qa
mkdir -p ~/.vim/autoload/
wget https://raw.githubusercontent.com/google/yapf/master/plugins/yapf.vim
mv yapf.vim ~/.vim/autoload
cp v ~/Application/bin/
