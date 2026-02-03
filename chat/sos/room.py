"""
SOS Room - Room management, emoji widgets, and state

Components:
- EmojiOTPInput: 6-box emoji picker for room ID entry
- PinInput: 6-digit PIN entry
- RoomDisplay: Creator's view with emoji ID + rotating/fixed key
- RoomManager: Room lifecycle management
"""

import time
import asyncio
from typing import Optional, Callable, Any
from dataclasses import dataclass, field

from textual.app import ComposeResult
from textual.widget import Widget
from textual.widgets import Static, Button, Input, Label
from textual.containers import Horizontal, Vertical, Container
from textual.reactive import reactive
from textual.message import Message as TextualMessage
from textual import on

# Support both absolute (PyInstaller) and relative (dev) imports
try:
    from sos.crypto import (
        EMOJI_SET, EMOJI_PHONETICS, 
        generate_room_id, generate_pin, get_current_pin, 
        get_time_remaining, room_id_to_hash, get_phonetic,
        RoomCredentials
    )
except ImportError:
    from .crypto import (
        EMOJI_SET, EMOJI_PHONETICS, 
        generate_room_id, generate_pin, get_current_pin, 
        get_time_remaining, room_id_to_hash, get_phonetic,
        RoomCredentials
    )


class EmojiBox(Static):
    """Single emoji display box"""
    
    DEFAULT_CSS = """
    EmojiBox {
        width: 5;
        height: 3;
        content-align: center middle;
        border: solid #444;
        margin: 0 1;
    }
    
    EmojiBox.selected {
        border: solid #00d4ff;
        background: #1a1a2e;
    }
    
    EmojiBox.filled {
        border: solid #00ff88;
    }
    """
    
    emoji: reactive[str] = reactive("")
    selected: reactive[bool] = reactive(False)
    
    def __init__(self, index: int = 0, **kwargs):
        super().__init__(**kwargs)
        self.index = index
    
    def watch_emoji(self, emoji: str):
        self.update(emoji if emoji else "·")
        self.set_class(bool(emoji), "filled")
    
    def watch_selected(self, selected: bool):
        self.set_class(selected, "selected")


class EmojiPicker(Widget):
    """Grid picker for selecting emoji"""
    
    DEFAULT_CSS = """
    EmojiPicker {
        layout: grid;
        grid-size: 8 4;
        grid-gutter: 1;
        padding: 1;
        background: #0d1117;
        border: solid #30363d;
        height: auto;
        width: auto;
    }
    
    EmojiPicker Button {
        width: 4;
        height: 2;
        min-width: 4;
        padding: 0;
        content-align: center middle;
    }
    
    EmojiPicker Button:hover {
        background: #238636;
    }
    """
    
    class Selected(TextualMessage):
        """Emoji was selected"""
        def __init__(self, emoji: str, index: int):
            self.emoji = emoji
            self.index = index
            super().__init__()
    
    def compose(self) -> ComposeResult:
        for i, emoji in enumerate(EMOJI_SET):
            yield Button(emoji, id=f"emoji-{i}", classes="emoji-btn")
    
    @on(Button.Pressed)
    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id
        if btn_id and btn_id.startswith("emoji-"):
            index = int(btn_id.split("-")[1])
            self.post_message(self.Selected(EMOJI_SET[index], index))


class EmojiOTPInput(Widget):
    """6-box emoji OTP-style input for room ID"""
    
    DEFAULT_CSS = """
    EmojiOTPInput {
        height: auto;
        width: auto;
        padding: 1;
    }
    
    EmojiOTPInput .emoji-boxes {
        height: auto;
        width: auto;
    }
    
    EmojiOTPInput .picker-container {
        margin-top: 1;
    }
    """
    
    class RoomIDComplete(TextualMessage):
        """All 6 emojis entered"""
        def __init__(self, emojis: list[str]):
            self.emojis = emojis
            super().__init__()
    
    emojis: reactive[list] = reactive(list, init=False)
    current_box: reactive[int] = reactive(0)
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.emojis = [""] * 6
        self._boxes: list[EmojiBox] = []
    
    def compose(self) -> ComposeResult:
        with Horizontal(classes="emoji-boxes"):
            for i in range(6):
                box = EmojiBox(index=i, id=f"box-{i}")
                self._boxes.append(box)
                yield box
        
        with Container(classes="picker-container"):
            yield EmojiPicker(id="picker")
            yield Static("Select emoji for each box. Use ← → to navigate.", classes="hint")
    
    def on_mount(self):
        self._update_selection()
    
    def _update_selection(self):
        for i, box in enumerate(self._boxes):
            box.selected = (i == self.current_box)
    
    @on(EmojiPicker.Selected)
    def on_emoji_selected(self, event: EmojiPicker.Selected):
        if 0 <= self.current_box < 6:
            self.emojis[self.current_box] = event.emoji
            self._boxes[self.current_box].emoji = event.emoji
            
            # Move to next box
            if self.current_box < 5:
                self.current_box += 1
                self._update_selection()
            else:
                # All filled - check if complete
                if all(self.emojis):
                    self.post_message(self.RoomIDComplete(self.emojis.copy()))
    
    def action_next_box(self):
        if self.current_box < 5:
            self.current_box += 1
            self._update_selection()
    
    def action_prev_box(self):
        if self.current_box > 0:
            self.current_box -= 1
            self._update_selection()
    
    def action_clear_current(self):
        self.emojis[self.current_box] = ""
        self._boxes[self.current_box].emoji = ""
    
    def clear(self):
        """Reset all boxes"""
        self.emojis = [""] * 6
        self.current_box = 0
        for box in self._boxes:
            box.emoji = ""
        self._update_selection()


class PinInput(Widget):
    """6-digit PIN input"""
    
    DEFAULT_CSS = """
    PinInput {
        height: auto;
        width: auto;
    }
    
    PinInput .pin-boxes {
        height: 3;
    }
    
    PinInput .pin-box {
        width: 4;
        height: 3;
        content-align: center middle;
        border: solid #444;
        margin: 0 1;
    }
    
    PinInput .pin-box.filled {
        border: solid #00ff88;
    }
    
    PinInput Input {
        width: 30;
        margin-top: 1;
    }
    """
    
    class PinComplete(TextualMessage):
        """All 6 digits entered"""
        def __init__(self, pin: str):
            self.pin = pin
            super().__init__()
    
    pin: reactive[str] = reactive("")
    
    def compose(self) -> ComposeResult:
        with Horizontal(classes="pin-boxes"):
            for i in range(6):
                yield Static("·", id=f"pin-box-{i}", classes="pin-box")
        
        yield Input(placeholder="Enter 6-digit PIN", id="pin-input", max_length=6)
    
    @on(Input.Changed, "#pin-input")
    def on_pin_changed(self, event: Input.Changed):
        # Filter to digits only
        digits = ''.join(c for c in event.value if c.isdigit())[:6]
        
        # Update display
        for i in range(6):
            box = self.query_one(f"#pin-box-{i}", Static)
            if i < len(digits):
                box.update(digits[i])
                box.add_class("filled")
            else:
                box.update("·")
                box.remove_class("filled")
        
        self.pin = digits
        
        if len(digits) == 6:
            self.post_message(self.PinComplete(digits))
    
    def clear(self):
        """Reset PIN"""
        self.pin = ""
        inp = self.query_one("#pin-input", Input)
        inp.value = ""


class RoomKeyDisplay(Widget):
    """Display for room creator showing emoji ID and rotating/fixed key"""
    
    DEFAULT_CSS = """
    RoomKeyDisplay {
        height: auto;
        width: 100%;
        padding: 1;
        background: #0d1117;
        border: solid #30363d;
    }
    
    RoomKeyDisplay .room-id {
        text-align: center;
        text-style: bold;
        margin-bottom: 1;
    }
    
    RoomKeyDisplay .room-id-emojis {
        text-align: center;
        text-style: bold;
    }
    
    RoomKeyDisplay .phonetic {
        text-align: center;
        color: #8b949e;
        margin-bottom: 1;
    }
    
    RoomKeyDisplay .key-label {
        text-align: center;
        color: #8b949e;
    }
    
    RoomKeyDisplay .key-display {
        text-align: center;
        text-style: bold;
    }
    
    RoomKeyDisplay .key-rotating {
        color: #58a6ff;
    }
    
    RoomKeyDisplay .key-fixed {
        color: #f0883e;
    }
    
    RoomKeyDisplay .countdown {
        text-align: center;
        color: #8b949e;
        margin-top: 1;
    }
    
    RoomKeyDisplay .warning-banner {
        background: #3d2a1f;
        color: #f0883e;
        text-align: center;
        padding: 1;
        margin-top: 1;
        border: solid #f0883e;
    }
    
    RoomKeyDisplay .expires {
        text-align: center;
        color: #8b949e;
        margin-top: 1;
    }
    """
    
    countdown: reactive[int] = reactive(15)
    current_pin: reactive[str] = reactive("")
    
    def __init__(self, credentials: RoomCredentials, **kwargs):
        super().__init__(**kwargs)
        self.credentials = credentials
        self._timer_task: Optional[asyncio.Task] = None
    
    def compose(self) -> ComposeResult:
        emoji_str = " ".join(self.credentials.emojis)
        phonetic = " · ".join(get_phonetic(e) for e in self.credentials.emojis)
        
        yield Static("📍 Room ID", classes="room-id")
        yield Static(emoji_str, classes="room-id-emojis")
        yield Static(f"({phonetic})", classes="phonetic")
        
        yield Static("🔑 Access Key", classes="key-label")
        
        if self.credentials.mode == "rotating":
            yield Static("------", id="key-value", classes="key-display key-rotating")
            yield Static("Rotates in 15s", id="countdown", classes="countdown")
        else:
            yield Static(self.credentials.fixed_pin or "------", id="key-value", classes="key-display key-fixed")
            yield Static(
                "⚠ Fixed key mode - less secure",
                classes="warning-banner"
            )
        
        # Room expiry countdown
        remaining = int(self.credentials.created_at + 3600 - time.time())
        mins = remaining // 60
        yield Static(f"Room expires in {mins} minutes", id="expires", classes="expires")
    
    async def on_mount(self):
        if self.credentials.mode == "rotating":
            self._timer_task = asyncio.create_task(self._rotation_timer())
        self._update_key_display()
    
    async def on_unmount(self):
        if self._timer_task:
            self._timer_task.cancel()
    
    async def _rotation_timer(self):
        """Update countdown and key every second"""
        while True:
            try:
                self.countdown = get_time_remaining()
                self._update_key_display()
                await asyncio.sleep(1)
            except asyncio.CancelledError:
                break
    
    def _update_key_display(self):
        key_widget = self.query_one("#key-value", Static)
        
        if self.credentials.mode == "rotating":
            new_pin = get_current_pin(self.credentials)
            if new_pin != self.current_pin:
                self.current_pin = new_pin
            key_widget.update(f"  {self.current_pin}  ")
            
            countdown_widget = self.query_one("#countdown", Static)
            countdown_widget.update(f"Rotates in {self.countdown}s")
        else:
            key_widget.update(f"  {self.credentials.fixed_pin}  ")
        
        # Update expiry
        remaining = int(self.credentials.created_at + 3600 - time.time())
        mins = max(0, remaining // 60)
        secs = max(0, remaining % 60)
        expires_widget = self.query_one("#expires", Static)
        expires_widget.update(f"Room expires in {mins}:{secs:02d}")


@dataclass
class Room:
    """Room state container"""
    credentials: RoomCredentials
    members: list[str] = field(default_factory=list)
    messages: list[dict] = field(default_factory=list)
    is_creator: bool = False
    nickname: str = "anon"
    
    @property
    def room_hash(self) -> str:
        return room_id_to_hash(self.credentials.emojis)
    
    @property
    def expires_at(self) -> float:
        return self.credentials.created_at + 3600  # 1 hour
    
    @property
    def time_remaining(self) -> int:
        return max(0, int(self.expires_at - time.time()))
    
    @property
    def is_expired(self) -> bool:
        return time.time() > self.expires_at


def create_room(mode: str = "rotating") -> Room:
    """Create a new room with fresh credentials"""
    emojis = generate_room_id()
    created_at = time.time()
    
    credentials = RoomCredentials(
        room_id=''.join(emojis),
        emojis=emojis,
        mode=mode,
        created_at=created_at,
        fixed_pin=generate_pin() if mode == "fixed" else None
    )
    
    return Room(
        credentials=credentials,
        is_creator=True,
        members=["You"]
    )


def join_room(emojis: list[str], mode: str = "rotating", created_at: float = 0) -> Room:
    """Join an existing room"""
    credentials = RoomCredentials(
        room_id=''.join(emojis),
        emojis=emojis,
        mode=mode,
        created_at=created_at or time.time()
    )
    
    return Room(
        credentials=credentials,
        is_creator=False
    )
