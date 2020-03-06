#!/usr/bin/env sh

pip install jupyter_contrib_nbextensions
jupyter contrib nbextension install --user
# --user to install into the user's home jupyter directories
# --system to perform installation into system-wide jupyter directories
# --sys-prefix to install into python's sys.prefix, useful for instance in virtual environments, such as with conda
# --symlink to symlink the nbextensions rather than copying each file (recommended, on non-Windows platforms).
# --debug, for more-verbose output

mkdir -p $(jupyter --data-dir)/nbextensions
cd $(jupyter --data-dir)/nbextensions
git clone https://github.com/lambdalisue/jupyter-vim-binding vim_binding
chmod -R go-w vim_binding


jupyter nbextension enable vim_binding/vim_binding
# 127.0.0.1:8888/nbextensions to check these extensions


pip install jupytext --upgrade
if [[ ! -f ~/.jupyter/jupyter_notebook_config.py ]]; then
    jupyter notebook --generate-config
fi

cat >> ~/.jupyter/jupyter_notebook_config.py << eof
c.NotebookApp.contents_manager_class="jupytext.TextFileContentsManager"
c.ContentsManager.default_jupytext_formats = ".ipynb,.py"
eof
