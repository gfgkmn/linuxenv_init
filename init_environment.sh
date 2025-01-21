#! /bin/bash

init-vim() {
	current_folder=$(pwd)

	if [ ! -d ~/.vimbakfiles ]; then
		mkdir ~/.vimbakfiles
	fi

	if [ ! -d ~/.vim/vundles ]; then
		mkdir -p ~/.vim/vundles/
	fi
	if [[ ! -d ~/.vim/vundles/vim-plug ]]; then
		cd ~/.vim/vundles || exit
		git clone https://github.com/junegunn/vim-plug.git
	fi
	cd "$current_folder" || exit
	cp vimrc ~/.vimrc
	if [ ! -d ~/.vim/autoload ]; then
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
}

if command -v lsb_release >/dev/null 2>&1; then
    RELEASE=$(lsb_release -a | grep Distributor | awk -F " " '{print $3}')
else
    if [ -f /etc/issue ]; then
        RELEASE=$(cat /etc/issue | awk '{print $1}' | head -n1)
    else
        echo "Cannot determine distribution"
        exit 1
    fi
fi

echo "Distribution: $RELEASE"

if [[ "RedHatEnterpriseServer" = "$RELEASE" || "CentOS" = "$RELEASE" ]]; then
	sudo yum install ctags
	sudo yum install build-essential cmake
	sudo yum install python-dev python3-dev
	sudo yum install mutt msmtp
	sudo yum install epel-release
	sudo yum install the_silver_searcher
	sudo yum install xclip
else
	sudo apt-get install -y build-essential cmake
	sudo apt-get install -y python-dev python3-dev
	sudo apt-get install -y libjansson-dev # ctags needs json
	sudo apt-get install -y mutt msmtp jq
	sudo apt-get install -y silversearcher-ag
	sudo apt-get install -y gcc make pkg-config autoconf automake python3-docutils libseccomp-dev libjansson-dev libyaml-dev libxml2-dev
	sudo apt-get install -y cargo

fi

if [ ! -d ~/Application/bin ]; then
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

if [[ ! -f ~/Application/bin/fasd ]]; then
	cp fasd ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/check_gpu.py ]]; then
	cp check_gpu.py ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/monitor.sh ]]; then
	cp monitor.sh ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/imgcat ]]; then
	cp imgcat ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/z.sh ]]; then
	cp z.sh ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/pbcopy ]]; then
	cp pbcopy ~/Application/bin/
fi
if [[ ! -f ~/.pip/pip.conf ]]; then
	mkdir ~/.pip/
	cp ./pip.conf ~/.pip/
fi

if [ ! -d ~/.ipython/profile_default ]; then
	mkdir -p ~/.ipython/profile_default
	cp ipython_config.py ~/.ipython/profile_default
	mkdir -p ~/.ipython/profile_default/startup/
	cp 00-forimport.py ~/.ipython/profile_default/startup/
fi
cp .inputrc ~/

curl -L https://iterm2.com/shell_integration/install_shell_integration.sh | bash

ssh-keygen -t rsa -N ''

cat >>~/.ssh/authorized_keys <<eof
ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA0ZzwzAjt7F4xOD4E0TKreAVUQKC8htT2n0DsjVximdIeaiXB24RDmYR7Hv05Iu9Mbc4K/MRrEMbKSBTEr15MN5LKZFNWpmC2V0ur5iq+hsPGMZoQ8ixB+YAmBw00I3qkEG/ceEaVX7zXLffLo+oahJEyYRWOIAUIW1Cligfs90OljX/lvzbVC+UASK950eAKWaTFlTVW1VKz6uhGOzqlbZBI+lIN1G0bLU+14XCz3rvlv2dgZCEuLZWEpC55iQllfJirmohjBBOuw7StbvRH4bLTne12ahoXDGpM0Bflawa8werv/Qp0/ib4vHeUV7sZu4STKkADjQP7ByiZwgrhcw== gfgkmn@gmail.com
eof

chmod 600 ~/.ssh/authorized_keys

if [[ ! -f ~/Application/mailtemplete ]]; then
	cp -r ./mailtemplete ~/Application/
fi

git config --global user.email "gfgkmn@gmail.com"
git config --global user.name "yuhe"

git clone git@github.com:universal-ctags/ctags.git
cd ctags || exit
./autogen.sh
./configure --prefix=/home/yuhe/Application --enable-json # defaults to /usr/local
make
make install # may require extra privileges depending on where to install

cat minibashrc >> ~/.bashrc

curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | bash
source $HOME/.atuin/bin/env
