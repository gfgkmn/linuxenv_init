c = get_config()
c.InteractiveShellApp.exec_lines.append('%reload_ext autoreload')
c.InteractiveShellApp.exec_lines.append('%autoreload 2')
c.TerminalInteractiveShell.editing_mode = 'vi'
c.TerminalInteractiveShell.emacs_bindings_in_vi_insert_mode = False
c.TerminalInteractiveShell.timeoutlen = 0.5
c.TerminalInteractiveShell.prompt_includes_vi_mode = False
c.TerminalInteractiveShell.ttimeoutlen = 0.01

c.InteractiveShellApp.exec_lines = [
    """
    def pb_cmd(self, arg):
        '''pb <variable>: Probe any variable with enhanced type inspection.

        Examples:
            pb tensor     # Probe a PyTorch tensor
            pb my_dict    # Probe a dictionary
            pb model      # Probe a model object
            pb arr        # Probe a NumPy array
        '''
        try:
            # Import locally to avoid circular imports
            import torch
            import numpy as np
            from explorer import get_type

            # Try to get the variable
            obj = self.curframe_locals.get(arg)
            if obj is None:
                try:
                    obj = eval(arg, self.curframe.f_globals, self.curframe_locals)
                except:
                    print(f"Error: '{arg}' not found in current scope.")
                    return

            # Use our enhanced get_type function
            get_type(obj)

        except Exception as e:
            print(f"Error probing '{arg}': {e}")
            import traceback
            traceback.print_exc()

    # Install the pb command into IPdb
    try:
        import IPython.terminal.debugger
        IPython.terminal.debugger.TerminalPdb.do_pb = pb_cmd
        # Also add help for the command
        IPython.terminal.debugger.TerminalPdb.help_pb = lambda self: print(pb_cmd.__doc__)
    except ImportError:
        pass
    """
]
