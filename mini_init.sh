#!/usr/bin/env bash

RELEASE=$(lsb_release -a | grep Distributor | awk -F " " '{print $3}')

if [[ "RedHatEnterpriseServer" = "$RELEASE"  || "CentOS" = "$RELEASE" ]];
then
	sudo yum install epel-release
	sudo yum install the_silver_searcher
else
    sudo apt-get install -y silversearcher-ag
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
if [[ ! -f ~/Application/bin/fasd ]]; then
	cp fasd ~/Application/bin/
fi
if [[ ! -f ~/Application/bin/pbcopy ]]; then
	cp pbcopy ~/Application/bin/
fi

curl -L https://iterm2.com/shell_integration/install_shell_integration.sh | bash

cat minibashrc >> ~/.bashrc
