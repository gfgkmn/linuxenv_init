#! /bin/bash
cd vim || exit
make clean distclean
./configure --with-features=huge             --enable-multibyte             --enable-rubyinterp=yes --enable-python3interp=yes --with-python3-config-dir=/home/yuhe/Applications/python36/lib/python3.6/config-3.6m-x86_64-linux-gnu --enable-perlinterp=yes             --enable-luainterp=yes             --enable-gui=gtk2 --enable-cscope             --prefix=/home/yuhe/Applications/
make
make install
