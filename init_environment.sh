#! /bin/bash

init-vim() {
	current_folder=$(pwd)

	git clone git@github.com:universal-ctags/ctags.git
	cd ctags || exit
	./autogen.sh
	./configure --prefix=/home/yuhe/Application --enable-json # defaults to /usr/local
	make
	make install # may require extra privileges depending on where to install

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
	sudo yum install npm mono-devel openjdk-8-jre
	sudo yum install mutt msmtp
	sudo yum install epel-release
	sudo yum install the_silver_searcher
	sudo yum install xclip
else
	sudo apt-get install -y build-essential cmake
	sudo apt-get install -y python-dev python3-dev
	sudo apt-get install -y libjansson-dev # ctags needs json
	sudo apt-get install -y npm mono-devel openjdk-8-jre
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

# if brew not install, install home brew
if ! command -v brew &>/dev/null; then
	echo "Brew not found. Installing..."
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	echo >>~/.bashrc
	echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >>~/.bashrc
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
else
	echo "Brew is already installed"
fi

# install aichat node go if not installed
if ! command -v aichat &>/dev/null; then
	echo "Aichat not found. Installing..."
	brew install aichat
else
	echo "Aichat is already installed"
fi

if ! command -v node &>/dev/null; then
	echo "Node not found. Installing..."
	brew install node
else
	echo "Node is already installed"
fi

if ! command -v go &>/dev/null; then
	echo "Go not found. Installing..."
	brew install go
else
	echo "Go is already installed"
fi

if ! command -v fd &>/dev/null; then
	echo "fd not found. Installing..."
	brew install fd
else
	echo "fd is already installed"
fi

if [ ! -d ~/Application/snippets ]; then
	git clone git@github.com:gfgkmn/snippets.git
	cp -r snippets ~/Application/snippets
	pip install -r ~/Application/snippets/requirements.txt
fi

if [[ ! -d ~/Application/fzf ]]; then
	git clone --depth 1 https://github.com/junegunn/fzf.git
	mv fzf ~/Application/
	~/Application/fzf/install
fi

if [[ ! -d ~/Application/ycmd ]]; then
	git clone git@github.com:gfgkmn/ycmd.git
	mv ycmd ~/Application
	cd ~/Application/ycmd || exit
	git submodule update --init --recursive
	python build.py --all
fi

if [[ ! -f ~/Application/bin/json_probe ]]; then
	cp ./bin/json_probe ~/Application/bin/
	chmod +x ~/Application/bin/json_probe
fi
if [[ ! -f ~/Application/bin/fasd ]]; then
	cp ./bin/fasd ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/check_gpu.py ]]; then
	cp ./bin/check_gpu.py ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/monitor.sh ]]; then
	cp ./bin/monitor.sh ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/imgcat ]]; then
	cp ./bin/imgcat ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/pbcopy ]]; then
	cp ./bin/pbcopy ~/Application/bin/
	chmod +x ~/Application/bin/pbcopy
fi
if [[ ! -f ~/Application/bin/display_gpu_info ]]; then
	cp ./bin/display_gpu_info ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/tableprobe ]]; then
	cp ./bin/tableprobe ~/Application/bin/
fi

if [[ ! -f ~/.pip/pip.conf ]]; then
	mkdir ~/.pip/
	cp ./pip.conf ~/.pip/
fi

if [ ! -f ~/.ipython/profile_default/ipython_config.py ]; then
	mkdir -p ~/.ipython/profile_default
	cp ipython_config.py ~/.ipython/profile_default/
fi

if [ ! -f ~/.ipython/profile_default/startup/00-forimport.py ]; then
	mkdir -p ~/.ipython/profile_default/startup/
	cp 00-forimport.py ~/.ipython/profile_default/startup/
fi

if [ ! -d ~/.ipython/extensions ]; then
	cp -R extensions ~/.ipython/
fi

if [[ ! -d ~/.inputrc ]]; then
	cp .inputrc ~/
fi

if [[ ! -f ~/.iterm2_shell_integration.bash ]]; then
	curl -L https://iterm2.com/shell_integration/install_shell_integration.sh | bash
fi

if [[ ! -f ~/.ssh/id_rsa ]]; then
	ssh-keygen -t rsa -N ''
	cat >>~/.ssh/authorized_keys <<eof
	ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA0ZzwzAjt7F4xOD4E0TKreAVUQKC8htT2n0DsjVximdIeaiXB24RDmYR7Hv05Iu9Mbc4K/MRrEMbKSBTEr15MN5LKZFNWpmC2V0ur5iq+hsPGMZoQ8ixB+YAmBw00I3qkEG/ceEaVX7zXLffLo+oahJEyYRWOIAUIW1Cligfs90OljX/lvzbVC+UASK950eAKWaTFlTVW1VKz6uhGOzqlbZBI+lIN1G0bLU+14XCz3rvlv2dgZCEuLZWEpC55iQllfJirmohjBBOuw7StbvRH4bLTne12ahoXDGpM0Bflawa8werv/Qp0/ib4vHeUV7sZu4STKkADjQP7ByiZwgrhcw== gfgkmn@gmail.com
eof

	chmod 600 ~/.ssh/authorized_keys
fi

if [[ ! -f ~/Application/mailtemplete ]]; then
	cp -r ./mailtemplete ~/Application/
fi

git config --global user.email "gfgkmn@gmail.com"
git config --global user.name "yuhe"

if ! command -v atuin &>/dev/null; then
	echo "Atuin not found. Installing..."
	curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | bash
	source $HOME/.atuin/bin/env
else
	echo "Atuin is already installed"
fi
