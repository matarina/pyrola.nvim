"""Pyrola's prompt-toolkit Enter/Ctrl-C handlers, including multiline input."""
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'rplugin/python3'))
from console import ReplInterpreter
from prompt_toolkit.keys import Keys

class ConsoleKeys(unittest.TestCase):
    def setUp(self):
        self.repl = ReplInterpreter.__new__(ReplInterpreter)
        self.repl._auto_indent = True
        self.repl.buffer = []
        self.repl.in_multiline = False
        self.repl._executing = False
        self.repl._interrupt_requested = False
        self.repl._interrupt_kernel = Mock()
        self.repl.handle_is_complete = Mock(return_value=('complete', ''))
        self.buffer = Mock()
        self.buffer.document.text = 'answer = 42'
        self.event = SimpleNamespace(current_buffer=self.buffer)
        bindings = self.repl._create_keybindings()
        self.enter = bindings.get_bindings_for_keys((Keys.ControlM,))[-1].handler
        self.interrupt = bindings.get_bindings_for_keys((Keys.ControlC,))[-1].handler

    def test_enter_complete(self):
        self.enter(self.event)
        self.buffer.validate_and_handle.assert_called_once()

    def test_enter_multiline(self):
        self.repl.handle_is_complete.return_value = ('incomplete', '    ')
        self.enter(self.event)
        self.buffer.newline.assert_called_once()
        self.buffer.insert_text.assert_called_once_with('    ')
        self.assertTrue(self.repl.in_multiline)
        self.buffer.validate_and_handle.assert_not_called()

    def test_enter_blank(self):
        self.buffer.document.text = ' '
        self.repl.in_multiline = True
        self.enter(self.event)
        self.buffer.validate_and_handle.assert_called_once()
        self.assertFalse(self.repl.in_multiline)

    def test_enter_blank_buffered(self):
        self.buffer.document.text = ''
        self.repl.buffer = ['for i in range(2):']
        self.enter(self.event)
        self.buffer.newline.assert_called_once()

    @patch('builtins.print')
    def test_ctrl_c_idle(self, _):
        self.repl.in_multiline = True
        self.interrupt(self.event)
        self.buffer.reset.assert_called_once()
        self.assertFalse(self.repl.in_multiline)
        self.repl._interrupt_kernel.assert_not_called()

    def test_ctrl_c_executing(self):
        self.repl._executing = True
        self.interrupt(self.event)
        self.repl._interrupt_kernel.assert_called_once()
        self.assertTrue(self.repl._interrupt_requested)
        self.buffer.reset.assert_not_called()

if __name__ == '__main__':
    unittest.main()
