#! /bin/bash

RELEASE=$(lsb_release -a | grep Distributor | awk -F " " '{print $3}')

if [[ "RedHatEnterpriseServer" = "$RELEASE"  || "CentOS" = "$RELEASE" ]];
then
	sudo yum install ctags
	sudo yum install build-essential cmake
	sudo yum install python-dev python3-dev
	sudo yum install mutt msmtp
else
	sudo apt-get install ctags
	sudo apt-get install build-essential cmake
	sudo apt-get install python-dev python3-dev
	sudo apt-get install mutt msmtp
fi

if [ ! -d ~/.vimbakfiles ]
then
	mkdir ~/.vimbakfiles
fi

if [ ! -d ~/.vim/vundls ]
then
	mkdir -p ~/.vim/vundles/
fi

if [ ! -d ~/Applications/bin ]
then
	mkdir -p ~/Application/bin
fi
if [[ ! -d ~/Application/PathPicker ]]; then
	git clone https://github.com/facebook/PathPicker.git
	mv PathPicker ~/Application
	ln -s ~/Application/PathPicker/fpp ~/Application/bin/fpp
fi
if [[ ! -d ~/Application/fzf ]]; then
	git clone --depth 1 https://github.com/junegunn/fzf.git
	mv fzf ~/Application/
	~/Application/fzf/install
fi
if [ ! -d ~/.ipython/profile_default ]
then
	mkdir -p ~/.ipython/profile_default
	cp ipython_config.py ~/.ipython/profile_default
fi
cp ./.inputrc ~/
current_folder=$(pwd)
if [[ ! -d ~/.vim/vundles/vim-plug ]]; then
	cd ~/.vim/vundles || exit
	git clone https://github.com/junegunn/vim-plug.git
fi
cd "$current_folder" || exit
cp .vimrc ~/
if [ ! -d ~/.vim/autoload ]
then
	mkdir -p ~/.vim/autoload
	cp ~/.vim/vundles/vim-plug/plug.vim ~/.vim/autoload/
fi
vim -c 'PlugUpdate' -c qa
# cd ~/.vim/vundles/YouCompleteMe/ || exit
# git submodule update --init --recursive
# ./install.py --clang-completer
if [[ ! -f ~/.vim/autoload/yapf.vim ]]; then
	wget https://raw.githubusercontent.com/google/yapf/master/plugins/vim/autoload/yapf.vim
	mv yapf.vim ~/.vim/autoload
fi
if [[ ! -f ~/Application/bin/fasd ]]; then
	cp fasd ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/pbcopy ]]; then
	wget https://raw.githubusercontent.com/skaji/remote-pbcopy-iterm2/master/pbcopy
	cp pbcopy ~/Application/bin/
fi
if [[ ! -f ~/.pip/pip.conf ]]; then
	mkdir ~/.pip/
	cp ./pip.conf ~/.pip/
fi
cat bashrc >> ~/.bashrc

if [[ ! -f ~/Application/mailtemplete ]]; then
	cp -r ./mailtemplete ~/Application/
fi

wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh
wget https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh

# bash Miniconda2-latest-Linux-x86_64.sh
# bash Miniconda3-latest-Linux-x86_64.sh
#
git clone https://github.com/vim/vim.git

# wget https://www.kernel.org/pub/software/scm/git/git-2.16.2.tar.xz
