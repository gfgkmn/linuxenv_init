#!/usr/bin/env python

import json
import copy
import os
import re
import sys
import traceback
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

# Your existing warning setup
def custom_formatwarning(message, category, filename, lineno, line=None):
    return f'{message}\n'

if sys.platform == 'darwin':
    import warnings
    warnings.formatwarning = custom_formatwarning
    warnings.warn("Please use fireducks on MacOS to get better performance.")

from ipykernel.iostream import OutStream
from IPython.core.getipython import get_ipython
from IPython.core.magic import (Magics, line_magic, magics_class, register_line_magic)
from chatgpt_v3 import Chatbot

# Configuration loading
__configpath = os.path.join(os.getenv('HOME'), '.config', 'chatgptel.json')
bots = json.load(open(__configpath, 'r'))
bots['pythongpt']["identity"] = Chatbot(**bots['pythongpt']["born_setting"])
__history_len = 0
__last_exception = None

@magics_class
class JupyterChatGPTMagics(Magics):

    @line_magic
    def ask(self, line):
        """ChatGPT magic command for Jupyter notebooks"""
        functions = [{
            "name": "python",
            "description": "Execute Python code in the REPL.",
            "parameters": {
                "type": "object",
                "properties": {
                    "code": {
                        "type": "string",
                        "description": "The Python code to run",
                    },
                },
            },
        }]

        stream_reply = bots["pythongpt"]["identity"].ask_stream(
            line, functions=functions, **bots["pythongpt"]["gen_setting"])

        print("[ChatGPT]: ")

        response = ""
        while True:
            try:
                chunk = next(stream_reply)
                print(chunk, end='', flush=True)
                response += chunk
            except StopIteration:
                print()  # New line at the end
                break

        return response

class JupyterTee:
    """Custom output capturer for Jupyter notebooks"""

    def __init__(self, original_stdout):
        self.stdout = original_stdout
        self.ipython = get_ipython()

    def write(self, message):
        if not isinstance(message, str):
            message = message.decode('utf-8')
        self.stdout.write(message)

        if message.strip():
            cell_index = self.ipython.execution_count
            if cell_index not in self.ipython.user_ns.get('_oh', {}):
                if '_oh' not in self.ipython.user_ns:
                    self.ipython.user_ns['_oh'] = {}
                self.ipython.user_ns['_oh'][cell_index] = message
            elif (isinstance(self.ipython.user_ns['_oh'].get(cell_index), str) and
                  self.ipython.user_ns['_oh'][cell_index].startswith('[ChatGPT]')):
                self.ipython.user_ns['_oh'][cell_index] += message

    def flush(self):
        self.stdout.flush()

def start_jupyter_capture(*args, **kwargs):
    """Start capturing output in Jupyter"""
    sys.stdout = JupyterTee(sys.stdout)

def stop_jupyter_capture(*args, **kwargs):
    """Stop capturing and process the conversation"""
    if hasattr(sys.stdout, 'stdout'):
        sys.stdout = sys.stdout.stdout

    ipython = get_ipython()
    global __history_len, __last_exception

    if len(ipython.user_ns.get('_ih', [])) > __history_len:
        cell_index = len(ipython.user_ns['_ih']) - 1
        recent_output = ipython.user_ns.get('_oh', {}).get(cell_index, '')

        try:
            recent_input = ipython.user_ns['_ih'][cell_index]
            if recent_input and not re.match(r'^\s*get_ipython\(\).run_line_magic\(\'ask', recent_input):
                format_turn_str = (f">>> {recent_input}\n{recent_output}"
                                 if recent_output else f">>> {recent_input}")
                bots['pythongpt']['identity'].add_to_conversation(format_turn_str, role="user")
                __history_len = len(ipython.user_ns.get('_oh', {}))
            else:
                if bots['pythongpt']['identity'].request_type == 'code':
                    ipython.set_next_input(
                        bots['pythongpt']['identity'].conversation['default'][-1]['content'])
                    bots['pythongpt']['identity'].request_type = 'reset'
        except (IndexError, KeyError):
            pass

    # Handle exceptions
    current_trace = getattr(sys, 'last_traceback', None)
    if __last_exception != current_trace and current_trace is not None:
        recent_input = ipython.user_ns['_ih'][-1]

        if sys.version_info >= (3, 10):
            recent_output = ''.join(
                traceback.format_exception(sys.last_type,
                                         value=sys.last_value,
                                         tb=sys.last_traceback))
        else:
            recent_output = ''.join(
                traceback.format_exception(etype=sys.last_type,
                                         value=sys.last_value,
                                         tb=sys.last_traceback))

        format_turn_str = f">>> {recent_input}\n{recent_output}"
        bots['pythongpt']['identity'].add_to_conversation(format_turn_str, role="user")
        __last_exception = current_trace

def load_ipython_extension(ipython):
    """Load the extension when called with %load_ext"""
    ipython.events.register('pre_run_cell', start_jupyter_capture)
    ipython.events.register('post_run_cell', stop_jupyter_capture)
    ipython.register_magics(JupyterChatGPTMagics)
    print("ChatGPT Jupyter extension loaded successfully!")

def unload_ipython_extension(ipython):
    """Unload the extension"""
    ipython.events.unregister('pre_run_cell', start_jupyter_capture)
    ipython.events.unregister('post_run_cell', stop_jupyter_capture)

# For direct execution in notebook
def setup_jupyter_chatgpt():
    """Setup function to call directly in Jupyter notebook"""
    ipython = get_ipython()
    if ipython:
        load_ipython_extension(ipython)
    else:
        print("Not running in IPython/Jupyter environment")

# Auto-setup if running directly
if __name__ != '__main__':
    # This runs when the module is imported
    setup_jupyter_chatgpt()
