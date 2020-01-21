#! /bin/bash

RELEASE=$(lsb_release -a | grep Distributor | awk -F " " '{print $3}')

if [[ "RedHatEnterpriseServer" = "$RELEASE"  || "CentOS" = "$RELEASE" ]];
then
	sudo yum install ctags
	sudo yum install build-essential cmake
	sudo yum install python-dev python3-dev
	sudo yum install mutt msmtp
	sudo yum install xclip
else
	sudo apt-get install build-essential cmake
	sudo apt-get install python-dev python3-dev
    sudo apt-get install libjansson-dev # ctags needs json
	sudo apt-get install mutt msmtp
	sudo apt-get install xclip
    sudo apt-get install silversearcher-ag
    # sudo add-apt-repository ppa:hnakamur/universal-ctags
    # sudo apt-get install universal-ctags
    sudo apt-get install gcc make pkg-config autoconf automake python3-docutils libseccomp-dev libjansson-dev libyaml-dev libxml2-dev

fi

if [ ! -d ~/.vimbakfiles ]
then
	mkdir ~/.vimbakfiles
fi

if [ ! -d ~/.vim/vundls ]
then
	mkdir -p ~/.vim/vundles/
fi

if [ ! -d ~/Application/bin ]
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
    mkdir -p ~/.ipython/profile_default/startup/
    cp 00-forimport.py ~/.ipython/profile_default/startup/
fi
cp .inputrc ~/
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
	mv yapf.vim ~/.vim/autoload
fi
if [[ ! -d ~/.vim/UltiSnips ]]; then
    cp -R ./UltiSnips/ ~/.vim/
fi
if [[ ! -f ~/Application/bin/fasd ]]; then
	cp fasd ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/pbcopy ]]; then
	cp pbcopy ~/Application/bin/
fi
if [[ ! -f ~/.pip/pip.conf ]]; then
	mkdir ~/.pip/
	cp ./pip.conf ~/.pip/
fi

ssh-keygen -t rsa -N ''

cat >> ~/.ssh/authorized_keys << eof
ssh-rsa
AAAAB3NzaC1yc2EAAAABIwAAAQEA0ZzwzAjt7F4xOD4E0TKreAVUQKC8htT2n0DsjVximdIeaiXB24RDmYR7Hv05Iu9Mbc4K/MRrEMbKSBTEr15MN5LKZFNWpmC2V0ur5iq+hsPGMZoQ8ixB+YAmBw00I3qkEG/ceEaVX7zXLffLo+oahJEyYRWOIAUIW1Cligfs90OljX/lvzbVC+UASK950eAKWaTFlTVW1VKz6uhGOzqlbZBI+lIN1G0bLU+14XCz3rvlv2dgZCEuLZWEpC55iQllfJirmohjBBOuw7StbvRH4bLTne12ahoXDGpM0Bflawa8werv/Qp0/ib4vHeUV7sZu4STKkADjQP7ByiZwgrhcw==
gfgkmn@gmail.com
eof

chmod 600 ~/.ssh/authorized_keys

if [[ ! -f ~/Application/mailtemplete ]]; then
	cp -r ./mailtemplete ~/Application/
fi

git config --global user.email "gfgkmn@gmail.com"
git config --global user.name "yuhe"

# wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh
wget https://repo.continuum.io/miniconda/Miniconda3-4.5.4-Linux-x86_64.sh
wget https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh

# bash Miniconda2-latest-Linux-x86_64.sh
# bash Miniconda3-latest-Linux-x86_64.sh
#
git clone https://github.com/vim/vim.git

# wget https://www.kernel.org/pub/software/scm/git/git-2.16.2.tar.xz

# pip install -r requirements.txt

git clone git@github.com:universal-ctags/ctags.git
cd ctags
./autogen.sh
./configure --prefix=~/Application --enable-json # defaults to /usr/local
make
make install # may require extra privileges depending on where to install
