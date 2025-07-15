c = get_config()
c.InteractiveShellApp.exec_lines.append('%reload_ext autoreload')
c.InteractiveShellApp.exec_lines.append('%autoreload 2')

c.InteractiveShellApp.exec_lines = [
    """
    def _pb_cmd(self, arg):
        '''pb <tensor>: Probe PyTorch tensor details.'''
        try:
            import torch
            tensor = self.curframe_locals.get(arg)
            if tensor is None:
                tensor = eval(arg, self.curframe.f_globals, self.curframe_locals)

            if not isinstance(tensor, torch.Tensor):
                print(f"'{arg}' is not a PyTorch Tensor.")
                return

            print(f"Tensor information:")
            print(f"  Shape: {tensor.shape}")
            print(f"  Dtype: {tensor.dtype}")
            print(f"  Device: {tensor.device}")
            print(f"  Memory usage: {tensor.nelement() * tensor.element_size()} bytes")
            print(f"  Requires gradient: {tensor.requires_grad}")
            print(f"  Is contiguous: {tensor.is_contiguous()}")
            print(f"  Sum: {tensor.sum().item()}")

            # Check for NaN/Inf values
            if tensor.dtype.is_floating_point:
                has_nan = torch.isnan(tensor).any().item()
                has_inf = torch.isinf(tensor).any().item()
                print(f"  Contains NaN: {has_nan}")
                print(f"  Contains Inf: {has_inf}")

            # Print statistics if it's a floating point tensor
            if tensor.dtype.is_floating_point:
                print(f"  Min value: {tensor.min().item()}")
                print(f"  Max value: {tensor.max().item()}")
                print(f"  Mean value: {tensor.mean().item()}")
                print(f"  Std deviation: {tensor.std().item()}")

        except Exception as e:
            print(f"Error probing tensor '{arg}': {e}")

    import IPython.terminal.debugger
    IPython.terminal.debugger.TerminalPdb.do_pb = _pb_cmd
    """
]
