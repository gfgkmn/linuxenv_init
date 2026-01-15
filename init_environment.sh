#! /bin/bash

init-vim() {
	current_folder=$(pwd)

	git clone git@github.com:universal-ctags/ctags.git
	cd ctags || exit
	./autogen.sh
	./configure --prefix=/home/yuhe/Applications --enable-json # defaults to /usr/local
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

# if brew not install, install home brew first (moved up to use brew for dependencies)
if ! command -v brew &>/dev/null; then
	echo "Brew not found. Installing..."
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	echo >>~/.bashrc
	echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >>~/.bashrc
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
else
	echo "Brew is already installed"
fi

# Install dependencies via brew (no sudo required)
echo "Installing dependencies via Homebrew..."
brew install cmake
brew install jansson
brew install jq
brew install the_silver_searcher
brew install autoconf automake pkg-config
brew install libyaml
brew install rust

if [ ! -d ~/Applications/bin ]; then
	mkdir -p ~/Applications/bin
fi
if [[ ! -d ~/Applications/PathPicker ]]; then
	git clone https://github.com/facebook/PathPicker.git
	mv PathPicker ~/Applications
	ln -s ~/Applications/PathPicker/fpp ~/Applications/bin/fpp
fi


if [[ ! -d ~/.tmux-jump ]]; then
	git clone https://github.com/schasse/tmux-jump ~/.tmux-jump
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

if [ ! -d ~/Applications/snippets ]; then
	git clone git@github.com:gfgkmn/snippets.git
	cp -R snippets ~/Applications/snippets
	pip install -r ~/Applications/snippets/requirements.txt
fi

if [[ ! -d ~/Applications/fzf ]]; then
	git clone --depth 1 https://github.com/junegunn/fzf.git
	mv fzf ~/Applications/
	~/Applications/fzf/install
fi

if [[ ! -d ~/Applications/ycmd ]]; then
	git clone git@github.com:gfgkmn/ycmd.git
	mv ycmd ~/Applications
	cd ~/Applications/ycmd || exit
	git submodule update --init --recursive
	python build.py --all
fi

if [[ ! -f ~/Applications/bin/json_probe ]]; then
	cp ./bin/json_probe ~/Applications/bin/
	chmod +x ~/Applications/bin/json_probe
fi
if [[ ! -f ~/Applications/bin/fasd ]]; then
	cp ./bin/fasd ~/Applications/bin/
fi
if [[ ! -f ~/Applications/bin/check_gpu.py ]]; then
	cp ./bin/check_gpu.py ~/Applications/bin/
fi
if [[ ! -f ~/Applications/bin/monitor.sh ]]; then
	cp ./bin/monitor.sh ~/Applications/bin/
fi
if [[ ! -f ~/Applications/bin/imgcat ]]; then
	cp ./bin/imgcat ~/Applications/bin/
fi
if [[ ! -f ~/Applications/bin/pbcopy ]]; then
	cp ./bin/pbcopy ~/Applications/bin/
	chmod +x ~/Applications/bin/pbcopy
fi
if [[ ! -f ~/Applications/bin/display_gpu_info ]]; then
	cp ./bin/display_gpu_info ~/Applications/bin/
fi
if [[ ! -f ~/Applications/bin/tableprobe ]]; then
	cp ./bin/tableprobe ~/Applications/bin/
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

if [[ ! -f ~/.inputrc ]]; then
	cp .inputrc ~/
fi


if [[ ! -f ~/.tmux.conf ]]; then
	cp .tmux.conf ~/
fi

if [[ ! -f ~/.iterm2_shell_integration.bash ]]; then
	curl -L https://iterm2.com/shell_integration/install_shell_integration.sh | bash
fi

if [[ ! -f ~/.ssh/id_rsa ]]; then
	ssh-keygen -t rsa -N ''
	cat >>~/.ssh/authorized_keys <<EOF
ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA0ZzwzAjt7F4xOD4E0TKreAVUQKC8htT2n0DsjVximdIeaiXB24RDmYR7Hv05Iu9Mbc4K/MRrEMbKSBTEr15MN5LKZFNWpmC2V0ur5iq+hsPGMZoQ8ixB+YAmBw00I3qkEG/ceEaVX7zXLffLo+oahJEyYRWOIAUIW1Cligfs90OljX/lvzbVC+UASK950eAKWaTFlTVW1VKz6uhGOzqlbZBI+lIN1G0bLU+14XCz3rvlv2dgZCEuLZWEpC55iQllfJirmohjBBOuw7StbvRH4bLTne12ahoXDGpM0Bflawa8werv/Qp0/ib4vHeUV7sZu4STKkADjQP7ByiZwgrhcw== gfgkmn@gmail.com
EOF

	chmod 600 ~/.ssh/authorized_keys
fi

if [[ ! -d ~/Applications/mailtemplete ]]; then
	cp -r ./mailtemplete ~/Applications/
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
