import http.server
import json
import os
import re
import socket
import socketserver
import tempfile
import threading
import uuid
from pathlib import Path

from IPython import get_ipython
from IPython.core.display import HTML, display
from IPython.core.magic import Magics, line_magic, magics_class


@magics_class
class HTMLServerMagics(Magics):

    def __init__(self, shell):
        super().__init__(shell)
        self.server = None
        self.server_thread = None
        self.temp_dir = None
        self.port = 8899
        self.host = '0.0.0.0'  # Bind to all interfaces
        self.display_host = None  # Will be set to actual IP
        self.auto_serve = False

    def get_display_url(self):
        """Get URL for display (use actual IP)"""
        if self.display_host is None:
            self.display_host = self.get_external_ip()
        return f'http://{self.display_host}:{self.port}'

    def get_external_ip(self):
        """Get external IP address"""
        try:
            # Get local IP address by connecting to external DNS
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
            return local_ip
        except:
            # Fallback: try to get hostname IP
            try:
                return socket.gethostbyname(socket.gethostname())
            except:
                return "localhost"

    def start_server(self):
        """Start the internal HTML server"""
        # Set display host first
        self.display_host = self.get_external_ip()

        if self.server is not None:
            print(f"Server already running at: http://{self.display_host}:{self.port}")
            return

        # Create temporary directory for serving files
        self.temp_dir = tempfile.mkdtemp(prefix='jupyter_html_server_')

        # Create assets directory for CSS/JS
        assets_dir = Path(self.temp_dir) / 'assets'
        assets_dir.mkdir(exist_ok=True)

        # Store temp_dir reference for the handler
        temp_dir_ref = self.temp_dir

        # Custom handler to serve HTML files
        class CustomHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):

            def __init__(self, *args, **kwargs):
                super().__init__(*args, directory=temp_dir_ref, **kwargs)

            def end_headers(self):
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
                self.send_header('Access-Control-Allow-Headers', 'Content-Type')
                super().end_headers()

            def log_message(self, format, *args):
                # Suppress default logging
                pass

        try:
            self.server = socketserver.TCPServer((self.host, self.port),
                                                 CustomHTTPRequestHandler)
            self.server.allow_reuse_address = True
            self.server_thread = threading.Thread(target=self.server.serve_forever,
                                                  daemon=True)
            self.server_thread.start()

            print(f"HTML Server started at: http://{self.display_host}:{self.port}")
            print(f"Serving files from: {self.temp_dir}")

        except OSError as e:
            if "Address already in use" in str(e):
                self.port += 1
                self.start_server()
            else:
                raise e

    def stop_server(self):
        """Stop the HTML server"""
        if self.server:
            self.server.shutdown()
            self.server.server_close()
            self.server = None
            self.server_thread = None
            print("HTML Server stopped")

    def serve_html_content(self, html_content, filename=None):
        """Serve HTML content and return URL"""
        if self.server is None:
            self.start_server()

        if filename is None:
            filename = f"{uuid.uuid4().hex}.html"

        # Extract and serve CSS/JS assets
        html_content = self.extract_and_serve_assets(html_content)

        # Write HTML file
        file_path = Path(self.temp_dir) / filename
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(html_content)

        # Return actual IP URL
        url = f"{self.get_display_url()}/{filename}"
        return url

    def extract_and_serve_assets(self, html_content):
        """Extract inline CSS/JS and serve as separate files"""
        assets_dir = Path(self.temp_dir) / 'assets'

        # Extract and replace inline CSS
        css_pattern = r'<style[^>]*>(.*?)</style>'
        css_matches = re.findall(css_pattern, html_content, re.DOTALL)

        for i, css_content in enumerate(css_matches):
            css_filename = f"style_{i}_{uuid.uuid4().hex[:8]}.css"
            css_path = assets_dir / css_filename
            with open(css_path, 'w', encoding='utf-8') as f:
                f.write(css_content)

            # Replace inline style with link
            css_link = f'<link rel="stylesheet" href="assets/{css_filename}">'
            html_content = re.sub(css_pattern, css_link, html_content, count=1)

        # Extract and replace inline JavaScript
        js_pattern = r'<script[^>]*>(.*?)</script>'
        js_matches = re.findall(js_pattern, html_content, re.DOTALL)

        for i, js_content in enumerate(js_matches):
            if js_content.strip():  # Only process non-empty scripts
                js_filename = f"script_{i}_{uuid.uuid4().hex[:8]}.js"
                js_path = assets_dir / js_filename
                with open(js_path, 'w', encoding='utf-8') as f:
                    f.write(js_content)

                # Replace inline script with external script
                js_link = f'<script src="assets/{js_filename}"></script>'
                html_content = re.sub(js_pattern, js_link, html_content, count=1)

        return html_content

    @line_magic
    def html_server_start(self, line):
        """Start the HTML server"""
        if line.strip():
            try:
                self.port = int(line.strip())
            except ValueError:
                print("Invalid port number")
                return
        self.start_server()

    @line_magic
    def html_server_stop(self, line):
        """Stop the HTML server"""
        self.stop_server()

    @line_magic
    def html_server_auto(self, line):
        """Toggle auto-serving of HTML outputs"""
        if line.strip().lower() in ['on', 'true', '1']:
            self.auto_serve = True
            print("Auto HTML serving enabled")
        else:
            self.auto_serve = False
            print("Auto HTML serving disabled")


# Global instance
_html_server_instance = None


def get_html_server():
    """Get or create HTML server instance"""
    global _html_server_instance
    ip = get_ipython()
    if _html_server_instance is None:
        _html_server_instance = HTMLServerMagics(ip)
    return _html_server_instance


def serve_html(html_content, filename=None):
    """Convenience function to serve HTML content"""
    server = get_html_server()
    url = server.serve_html_content(html_content, filename)

    # Display clickable link with actual IP
    link_html = f'''
    <div style="border: 1px solid #ccc; padding: 10px; margin: 5px 0; background: #f9f9f9;">
        <strong>HTML Content served at:</strong><br>
        <a href="{url}" target="_blank" style="color: #0066cc; text-decoration: none;">
            📄 {url}
        </a>
        <br><small>Click to open in new tab • Accessible from remote machines</small>
    </div>
    '''
    display(HTML(link_html))
    return url


def load_ipython_extension(ipython):
    """Load the extension"""
    global _html_server_instance
    _html_server_instance = HTMLServerMagics(ipython)
    ipython.register_magic_function(_html_server_instance.html_server_start, 'line',
                                    'html_server_start')
    ipython.register_magic_function(_html_server_instance.html_server_stop, 'line',
                                    'html_server_stop')
    ipython.register_magic_function(_html_server_instance.html_server_auto, 'line',
                                    'html_server_auto')

    # Make serve_html available globally
    ipython.user_ns['serve_html'] = serve_html

    print("HTML Server Extension loaded!")
    print("Usage:")
    print("  %html_server_start [port]  - Start server (default port 8899)")
    print("  %html_server_stop          - Stop server")
    print("  %html_server_auto on/off   - Auto-serve HTML outputs")
    print("  serve_html(html_content)   - Serve HTML content directly")
    print("Server binds to 0.0.0.0 but displays real IP address")
