#! /bin/bash
cd vim || exit
./configure --with-features=huge             --enable-multibyte             --enable-rubyinterp=yes             --enable-pythoninterp=yes             --with-python-config-dir=/search/odin/yuhe/Application/python27/lib/python2.7/config             --enable-python3interp=yes             --with-python3-config-dir=/search/odin/yuhe/Application/python36/lib/python3.6/config-3.6m-x86_64-linux-gnu             --enable-perlinterp=yes             --enable-luainterp=yes             --enable-gui=gtk2             --enable-cscope             --prefix=/search/odin/yuhe/Application/
make
make install
