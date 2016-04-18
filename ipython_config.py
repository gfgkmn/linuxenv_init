c = get_config()
c.InteractiveShellApp.exec_lines.append('%reload_ext autoreload')
c.InteractiveShellApp.exec_lines.append('%autoreload 2')
