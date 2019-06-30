#! /bin/bash

RELEASE=$(lsb_release -a | grep Distributor | awk -F " " '{print $3}')

if [ "RedHatEnterpriseServer" = "$RELEASE" ];
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
unzip PathPicker-master.zip
mv PathPicker-master ~/Application/PathPicker
ln -s ~/Application/PathPicker/fpp ~/Application/bin/fpp
unzip fzf-master.zip
./fzf-master/install
if [ ! -d ~/.ipython/profile_default ]
then
	mkdir -p ~/.ipython/profile_default
fi
cp ipython_config.py ~/.ipython/profile_default
cp ./.inputrc ~/
current_folder=$(pwd)
unzip vim-plug-master.zip
mv vim-plug-master ~/.vim/vundles/vim-plug
cd "$current_folder" || exit
cp .vimrc ~/
if [ ! -d ~/.vim/autoload ]
then
	mkdir -p ~/.vim/autoload
fi
cp ~/.vim/vundles/vim-plug/plug.vim ~/.vim/autoload/
# vim -c 'PlugUpdate' -c qa
# cd ~/.vim/vundles/YouCompleteMe/ || exit
# git submodule update --init --recursive
# ./install.py --clang-completer
mv yapf.vim ~/.vim/autoload
cp fasd ~/Application/bin/
cp pbcopy ~/Application/bin/
mkdir ~/.pip/
cp ./pip.conf ~/.pip/
cat bashrc >> ~/.bashrc

cp -r ./mailtemplete ~/Application/

# wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh
# wget https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh

# bash Miniconda2-latest-Linux-x86_64.sh
# bash Miniconda3-latest-Linux-x86_64.sh
# 
# git clone https://github.com/vim/vim.git
unzip vim-master.zip
mv vim-master vim

# wget https://www.kernel.org/pub/software/scm/git/git-2.16.2.tar.xz
