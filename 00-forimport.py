import json
import os
import re
import sys
import traceback

import pandas as pd
from IPython.paths import get_ipython_dir


# echo a warning to prompt me to use fireducks on macos
def custom_formatwarning(message, category, filename, lineno, line=None):
    return f'{message}\n'


from chatgpt_v3 import Chatbot
from IPython.core.getipython import get_ipython
from IPython.core.magic import Magics, line_magic, magics_class

__configpath = os.path.join(os.getenv('HOME'), '.config', 'chatgptel.json')
# json check for config file
if not os.path.exists(__configpath):
    print(f"Warning: Configuration file not found at {__configpath}")
    print("Please create the chatgptel.json configuration file to use ChatGPT features.")
    bots = {}
else:
    try:
        bots = json.load(open(__configpath, 'r'))
        bots['pythongpt']["identity"] = Chatbot(**bots['pythongpt']["born_setting"])
    except (json.JSONDecodeError, KeyError) as e:
        print(f"Error loading configuration file: {e}")
        bots = {}

__history_len = 0
__last_exception = None

extensions_dir = os.path.join(get_ipython_dir(), "extensions")
if extensions_dir not in sys.path:
    sys.path.insert(0, extensions_dir)


@magics_class
class MyMagics(Magics):

    def _check_bot_available(self):
        if not bots or 'pythongpt' not in bots:
            print("ChatGPT bot not available. Please check your configuration.")
            return False
        return True

    @line_magic
    def ask(self, line):
        "My line magic function"
        # Implementation of your function here
        if not self._check_bot_available():
            return

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

        sys.stdout.write("[ChatGPT]: \n")
        sys.stdout.flush()

        while True:
            try:
                sys.stdout.write(next(stream_reply))
                sys.stdout.flush()
            except StopIteration:
                sys.stdout.write('\n')
                sys.stdout.flush()
                break

        # return bots['pythongpt']["identity"].ask(line, **bots['pythongpt']["gen_setting"])


class Tee:

    def __init__(self, original_stdout):
        self.stdout = original_stdout
        self.ipython = get_ipython()

    def write(self, message):
        # Write to original stdout
        if not isinstance(message, str):
            message = message.decode('utf-8')
        self.stdout.write(message)

        # Capture the output in IPython's _oh dictionary
        if message.strip():  # Only store non-empty messages
            cell_index = self.ipython.execution_count
            if cell_index not in self.ipython.user_ns['_oh']:
                self.ipython.user_ns['_oh'][cell_index] = message
            elif isinstance(self.ipython.user_ns['_oh'][cell_index],
                            str) and self.ipython.user_ns['_oh'][cell_index].startswith(
                                '[ChatGPT]'):
                self.ipython.user_ns['_oh'][cell_index] += message

    def flush(self):
        self.stdout.flush()


def start_capture(*args, **kwargs):
    sys.stdout = Tee(sys.stdout)


def stop_capture(*args, **kwargs):
    # sys.stdout = sys.__stdout__
    if not bots:
        return

    sys.stdout = sys.stdout.stdout

    ipython = get_ipython()
    global __history_len, __last_exception
    if len(ipython.user_ns['_ih']) > __history_len:
        cell_index = len(ipython.user_ns['_ih']) - 1
        recent_output = ipython.user_ns['_oh'].get(cell_index, '')

        try:
            recent_input = ipython.user_ns['_ih'][cell_index]
            if recent_input is None or recent_input == '':
                pass
            elif not re.match('^\s*get_ipython\(\).run_line_magic\(\'ask', recent_input):
                format_turn_str = f">>> {recent_input}\n{recent_output}" if recent_output is not None else f">>> {recent_input}"
                bots['pythongpt']['identity'].add_to_conversation(format_turn_str,
                                                                  role="user")
                __history_len = len(ipython.user_ns['_oh'])
            else:
                if bots['pythongpt']['identity'].request_type == 'code':
                    ipython.set_next_input(
                        bots['pythongpt']['identity'].conversation['default'][-1]
                        ['content'])
                    bots['pythongpt']['identity'].request_type = 'reset'
        except IndexError:
            pass

    current_trace = getattr(sys, 'last_traceback', None)
    if __last_exception != current_trace:
        # If there's exception info, an exception was caught
        recent_input = ipython.user_ns['_ih'][-1]

        if sys.version_info >= (3, 11):
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
            if bots and 'pythongpt' in bots:
                bots['pythongpt']['identity'].add_to_conversation(format_turn_str,
                                                                  role="user")
            __last_exception = current_trace


# Register our custom output capturing on IPython startup
get_ipython().events.register('pre_run_cell', start_capture)
get_ipython().events.register('post_run_cell', stop_capture)

get_ipython().register_magics(MyMagics)
