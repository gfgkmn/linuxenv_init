# sudo apt-get install ctags
sudo apt-get install build-essential cmake
sudo apt-get python-dev python3-dev
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
cd ~/.vim/vundles/YouCompleteMe/
git submodule update --init --recursive
cd $current_folder
cp .vimrc ~/
mkdir -p ~/.vim/autoload
cp ~/.vim/vundles/vim-plug/plug.vim ~/.vim/autoload/
vim -c 'PlugUpdate' -c qa
wget https://raw.githubusercontent.com/google/yapf/master/plugins/vim/autoload/yapf.vim  
mv yapf.vim ~/.vim/autoload
cp v ~/Application/bin/
wget https://raw.githubusercontent.com/skaji/remote-pbcopy-iterm2/master/pbcopy
cp pbcopy ~/Application/bin/
mkdir ~/.pip/
cp ./pip.conf ~/.pip/
git config --global user.email gfgkmn@gmail.com
git config --global user.name yuhe
cat bashrc >> ~/.bashrc

