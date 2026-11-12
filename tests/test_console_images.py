"""Floating images must work without the optional timg renderer."""
import asyncio
import base64
import io
import os
from threading import Lock
from PIL import Image
import sys
import tempfile
import unittest
from pathlib import Path
from queue import Queue
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'rplugin/python3'))
from console import ReplInterpreter

class ImageDeliveryTest(unittest.TestCase):
    def test_floating_image_without_timg(self):
        messages = [{'header': {'msg_type': 'display_data'}, 'parent_header': {'msg_id': 'cell'}, 'content': {'data': {'image/png': 'aW1hZ2U='}}}]
        repl = ReplInterpreter.__new__(ReplInterpreter)
        repl.client = SimpleNamespace(iopub_channel=SimpleNamespace(msg_ready=lambda: bool(messages)), get_iopub_msg=lambda: messages.pop(0))
        repl._pending_clearoutput = False
        repl._image_debug = False
        repl._image_max_height_ratio = 0.5
        repl._nvim_address = 'test-socket'
        repl._temp_paths = set()
        repl.nvim_queue = Queue()
        repl._start_nvim_thread = lambda: None
        with tempfile.TemporaryDirectory() as temp:
            repl._temp_dir = SimpleNamespace(name=temp)
            with patch.dict(os.environ, {'PYROLA_IMAGE_INLINE': 'blocks'}), patch('console.shutil.which', return_value=None):
                asyncio.run(repl.handle_iopub_msgs('cell'))
            self.assertEqual(repl.nvim_queue.get_nowait(), ('image', 'aW1hZ2U='))
            self.assertFalse(repl._temp_paths)
            self.assertFalse(list(Path(temp).iterdir()))

class InlineDeliveryTest(unittest.TestCase):
    def test_bitmap_output_bypasses_block_renderer(self):
        messages = [{'header': {'msg_type': 'display_data'}, 'parent_header': {'msg_id': 'cell'}, 'content': {'data': {'image/png': 'aW1hZ2U='}}}]
        repl = ReplInterpreter.__new__(ReplInterpreter)
        repl.client = SimpleNamespace(iopub_channel=SimpleNamespace(msg_ready=lambda: bool(messages)), get_iopub_msg=lambda: messages.pop(0))
        repl._pending_clearoutput = False
        repl._image_debug = False
        repl._image_max_height_ratio = 0.5
        repl._nvim_address = 'test-socket'
        repl._temp_paths = set()
        repl._start_nvim_thread = lambda: None
        class ReplyQueue(Queue):
            def put(self, item):
                assert item[0] == 'inline_image'
                item[1][3].set_result('INLINE_BITMAP_OUTPUT\n')
        repl.nvim_queue = ReplyQueue()
        captured = io.StringIO()
        with tempfile.TemporaryDirectory() as temp:
            repl._temp_dir = SimpleNamespace(name=temp)
            with patch.dict(os.environ, {'PYROLA_IMAGE_INLINE': 'kitty'}), patch('console.sys.stdout', captured), patch('console.asyncio.create_subprocess_exec') as block_renderer:
                asyncio.run(repl.handle_iopub_msgs('cell'))
                block_renderer.assert_not_called()
        self.assertEqual(captured.getvalue(), 'INLINE_BITMAP_OUTPUT\n')

class ImageResolutionTest(unittest.TestCase):
    def test_worker_preserves_original_raster(self):
        stream = io.BytesIO()
        Image.new('RGB', (1800, 1170), 'white').save(stream, format='PNG')
        payload = base64.b64encode(stream.getvalue()).decode()
        repl = ReplInterpreter.__new__(ReplInterpreter)
        repl.nvim_queue = Queue()
        repl.nvim_queue.put(('image', payload))
        repl.nvim_queue.put(None)
        repl.nvim_lock = Lock()
        repl._ensure_nvim = lambda: True
        repl._temp_paths = set()
        repl._image_debug = False
        captured = {}
        def command(value):
            if value.startswith('let g:pyrola_image_path'):
                captured['payload'] = Path(value.split('"')[1]).read_text()
            if value.startswith('let g:pyrola_image_width'):
                captured['width'] = value.split('=')[1].strip()
            if value.startswith('let g:pyrola_image_height'):
                captured['height'] = value.split('=')[1].strip()
        # No editor size/pixel APIs are provided: the worker must not use them.
        repl.nvim = SimpleNamespace(command=command)
        with tempfile.TemporaryDirectory() as temp:
            repl._temp_dir = SimpleNamespace(name=temp)
            repl._nvim_worker()
        self.assertEqual(captured['payload'], payload)
        self.assertEqual(captured['width'], '1800')
        self.assertEqual(captured['height'], '1170')

if __name__ == '__main__':
    unittest.main()
