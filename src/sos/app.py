"""
SOS App - Emergency Secure Chat TUI

Main application with screens:
- WelcomeScreen: Create or Join room, mode selection
- ChatRoomScreen: Chat interface with message log

Usage: python -m sos.app
"""

import time
import base64
import asyncio
from typing import Optional

from textual.app import App, ComposeResult
from textual.screen import Screen
from textual.widgets import (
    Header, Footer, Static, Button, Input, 
    RichLog, Label, RadioButton, RadioSet
)
from textual.containers import Horizontal, Vertical, Container, VerticalScroll
from textual.binding import Binding
from textual import on

from .crypto import (
    EMOJI_SET, get_current_pin, encrypt_message, decrypt_message,
    get_encryption_key, room_id_to_hash, get_phonetic_room_id,
    RoomCredentials
)
from .room import (
    Room, RoomKeyDisplay, EmojiOTPInput, PinInput,
    create_room, join_room
)
from .transport import SOSTransport, ConnectionState, Message, RateLimitError


# ASCII Banner
BANNER = """
[cyan]
    ▒▒▒▒▒▒▒╗ ▒▒▒▒▒▒╗ ▒▒▒▒▒▒▒╗
    ▒▒╔════╝▒▒╔═══▒▒╗▒▒╔════╝
    ▒▒▒▒▒▒▒╗▒▒║   ▒▒║▒▒▒▒▒▒▒╗
    ╚════▒▒║▒▒║   ▒▒║╚════▒▒║
    ▒▒▒▒▒▒▒║╚▒▒▒▒▒▒╔╝▒▒▒▒▒▒▒║
    ╚══════╝ ╚═════╝ ╚══════╝
[/cyan]
[dim]Emergency Secure Chat over DNS Tunnel[/dim]
"""


class WelcomeScreen(Screen):
    """Initial screen - Create or Join a room"""
    
    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("c", "create", "Create Room"),
        Binding("j", "join", "Join Room"),
    ]
    
    CSS = """
    WelcomeScreen {
        align: center middle;
    }
    
    .welcome-container {
        width: 70;
        height: auto;
        padding: 2;
        background: #0d1117;
        border: solid #30363d;
    }
    
    .banner {
        text-align: center;
        margin-bottom: 2;
    }
    
    .buttons {
        align: center middle;
        height: auto;
        margin-top: 2;
    }
    
    .buttons Button {
        margin: 0 2;
        min-width: 20;
    }
    
    .mode-select {
        margin-top: 2;
        padding: 1;
        background: #161b22;
        border: solid #30363d;
    }
    
    .mode-label {
        margin-bottom: 1;
        color: #8b949e;
    }
    
    .mode-warning {
        color: #f0883e;
        margin-top: 1;
        text-align: center;
    }
    
    .join-section {
        margin-top: 2;
        display: none;
    }
    
    .join-section.visible {
        display: block;
    }
    
    .status {
        text-align: center;
        margin-top: 1;
        color: #8b949e;
    }
    
    .error {
        color: #f85149;
        text-align: center;
        margin-top: 1;
    }
    """
    
    show_join: bool = False
    selected_mode: str = "rotating"
    
    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        
        with Container(classes="welcome-container"):
            yield Static(BANNER, classes="banner")
            
            # Mode selection
            with Vertical(classes="mode-select"):
                yield Static("Key Mode:", classes="mode-label")
                with RadioSet(id="mode-select"):
                    yield RadioButton("🔄 Rotating (changes every 15s)", id="mode-rotating", value=True)
                    yield RadioButton("📌 Fixed (static key)", id="mode-fixed")
                yield Static("", id="mode-warning", classes="mode-warning")
            
            # Main buttons
            with Horizontal(classes="buttons"):
                yield Button("Create Room", id="btn-create", variant="primary")
                yield Button("Join Room", id="btn-join", variant="default")
            
            # Join section (hidden by default)
            with Vertical(classes="join-section", id="join-section"):
                yield Static("Enter Room ID (6 emojis):", classes="mode-label")
                yield EmojiOTPInput(id="emoji-input")
                yield Static("Enter PIN (6 digits):", classes="mode-label")
                yield PinInput(id="pin-input")
                yield Button("Connect", id="btn-connect", variant="success")
            
            yield Static("", id="status", classes="status")
            yield Static("", id="error", classes="error")
        
        yield Footer()
    
    @on(RadioSet.Changed, "#mode-select")
    def on_mode_changed(self, event: RadioSet.Changed):
        warning = self.query_one("#mode-warning", Static)
        if event.pressed.id == "mode-fixed":
            self.selected_mode = "fixed"
            warning.update("⚠ Fixed mode is less secure - use only if necessary")
        else:
            self.selected_mode = "rotating"
            warning.update("")
    
    @on(Button.Pressed, "#btn-create")
    def on_create_pressed(self, event: Button.Pressed):
        self.action_create()
    
    @on(Button.Pressed, "#btn-join")
    def on_join_pressed(self, event: Button.Pressed):
        join_section = self.query_one("#join-section")
        join_section.toggle_class("visible")
        self.show_join = not self.show_join
        
        if self.show_join:
            self.query_one("#btn-join", Button).label = "Cancel"
        else:
            self.query_one("#btn-join", Button).label = "Join Room"
    
    @on(Button.Pressed, "#btn-connect")
    async def on_connect_pressed(self, event: Button.Pressed):
        await self._try_join()
    
    @on(EmojiOTPInput.RoomIDComplete)
    def on_room_id_complete(self, event: EmojiOTPInput.RoomIDComplete):
        # Focus PIN input
        self.query_one("#pin-input Input", Input).focus()
    
    @on(PinInput.PinComplete)
    async def on_pin_complete(self, event: PinInput.PinComplete):
        await self._try_join()
    
    async def _try_join(self):
        """Attempt to join a room"""
        emoji_input = self.query_one("#emoji-input", EmojiOTPInput)
        pin_input = self.query_one("#pin-input", PinInput)
        status = self.query_one("#status", Static)
        error = self.query_one("#error", Static)
        
        emojis = emoji_input.emojis
        pin = pin_input.pin
        
        if not all(emojis):
            error.update("Please enter all 6 emojis")
            return
        
        if len(pin) != 6:
            error.update("Please enter 6-digit PIN")
            return
        
        error.update("")
        status.update("Connecting...")
        
        # Create room and switch to chat
        room = join_room(emojis, mode=self.selected_mode)
        self.app.switch_screen(ChatRoomScreen(room, pin))
    
    def action_create(self):
        """Create a new room"""
        room = create_room(mode=self.selected_mode)
        self.app.switch_screen(ChatRoomScreen(room))
    
    def action_join(self):
        """Show join section"""
        self.on_join_pressed(None)
    
    def action_quit(self):
        self.app.exit()


class ChatRoomScreen(Screen):
    """Main chat room interface"""
    
    BINDINGS = [
        Binding("escape", "leave", "Leave Room"),
        Binding("ctrl+l", "clear_log", "Clear"),
    ]
    
    CSS = """
    ChatRoomScreen {
        layout: grid;
        grid-size: 1 1;
    }
    
    .chat-container {
        layout: grid;
        grid-size: 4 1;
        grid-columns: 1fr 3fr;
        height: 100%;
    }
    
    .sidebar {
        background: #0d1117;
        border-right: solid #30363d;
        padding: 1;
    }
    
    .main-area {
        layout: grid;
        grid-size: 1 2;
        grid-rows: 1fr auto;
        padding: 1;
    }
    
    .chat-log {
        border: solid #30363d;
        background: #010409;
        padding: 1;
    }
    
    .input-area {
        height: 5;
        padding: 1 0;
    }
    
    .input-area Input {
        width: 100%;
    }
    
    .members-label {
        color: #8b949e;
        margin-top: 1;
        margin-bottom: 1;
    }
    
    .members-list {
        height: auto;
    }
    
    .member {
        color: #58a6ff;
    }
    
    .connection-status {
        margin-top: 1;
        padding: 1;
        text-align: center;
    }
    
    .connection-status.connected {
        color: #3fb950;
    }
    
    .connection-status.disconnected {
        color: #f85149;
    }
    
    .connection-status.connecting {
        color: #f0883e;
    }
    
    .system-msg {
        color: #8b949e;
        text-style: italic;
    }
    
    .my-msg {
        color: #58a6ff;
    }
    
    .other-msg {
        color: #3fb950;
    }
    
    .waiting-banner {
        text-align: center;
        color: #f0883e;
        margin: 2;
        padding: 1;
        border: dashed #f0883e;
    }
    """
    
    def __init__(self, room: Room, join_pin: Optional[str] = None):
        super().__init__()
        self.room = room
        self.join_pin = join_pin  # PIN used to join (for validation)
        self.transport = SOSTransport()
        self.encryption_key: Optional[bytes] = None
        self._poll_task: Optional[asyncio.Task] = None
    
    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        
        with Horizontal(classes="chat-container"):
            # Sidebar with room info
            with Vertical(classes="sidebar"):
                yield RoomKeyDisplay(self.room.credentials, id="room-display")
                
                yield Static("Members:", classes="members-label")
                with VerticalScroll(classes="members-list", id="members-list"):
                    yield Static("• You", classes="member")
                
                yield Static("● Connected", id="conn-status", classes="connection-status connected")
            
            # Main chat area
            with Vertical(classes="main-area"):
                yield RichLog(id="chat-log", classes="chat-log", wrap=True, highlight=True, markup=True)
                
                with Horizontal(classes="input-area"):
                    yield Input(placeholder="Type message and press Enter...", id="msg-input")
        
        yield Footer()
    
    async def on_mount(self):
        """Initialize room connection"""
        log = self.query_one("#chat-log", RichLog)
        
        # Set up encryption key
        if self.room.is_creator:
            # Creator - show waiting message
            log.write("[dim]Room created. Share the Room ID and PIN with your contact.[/dim]")
            log.write("[dim]They need to enter the emojis and current PIN to join.[/dim]")
            log.write("")
            
            # Get current key
            current_pin = get_current_pin(self.room.credentials)
            self.encryption_key = get_encryption_key(self.room.credentials, current_pin)
        else:
            # Joiner - use provided PIN
            log.write("[dim]Joining room...[/dim]")
            if self.join_pin:
                self.encryption_key = get_encryption_key(self.room.credentials, self.join_pin)
        
        # Connect to relay
        self.transport.on_message = self._on_message_received
        self.transport.on_state_change = self._on_state_change
        self.transport.on_members_update = self._on_members_update
        self.transport.on_room_expire = self._on_room_expire
        
        connected = await self.transport.connect()
        
        if connected:
            if self.room.is_creator:
                room_hash = self.room.room_hash
                result = await self.transport.create_room(room_hash, self.room.credentials.mode)
                if result:
                    log.write("[green]✓ Room ready. Waiting for others to join...[/green]")
                    await self.transport.start_polling()
                else:
                    log.write("[red]✗ Failed to create room on server[/red]")
            else:
                room_hash = room_id_to_hash(self.room.credentials.emojis)
                result = await self.transport.join_room(room_hash, "anon")
                if result:
                    log.write("[green]✓ Joined room successfully![/green]")
                    # Update room info from server
                    self.room.credentials.created_at = result.created_at
                    await self.transport.start_polling()
                else:
                    log.write("[red]✗ Failed to join room. Check Room ID and PIN.[/red]")
        else:
            log.write("[yellow]⚠ Running in offline mode (no relay connection)[/yellow]")
        
        # Focus input
        self.query_one("#msg-input", Input).focus()
    
    async def on_unmount(self):
        """Cleanup on exit"""
        await self.transport.leave_room()
    
    @on(Input.Submitted, "#msg-input")
    async def on_message_submitted(self, event: Input.Submitted):
        """Send a message"""
        message = event.value.strip()
        if not message:
            return
        
        # Clear input
        event.input.value = ""
        
        log = self.query_one("#chat-log", RichLog)
        
        # Encrypt message
        if self.encryption_key:
            try:
                # Update key for rotating mode
                if self.room.credentials.mode == "rotating":
                    current_pin = get_current_pin(self.room.credentials)
                    self.encryption_key = get_encryption_key(self.room.credentials, current_pin)
                
                encrypted = encrypt_message(message, self.encryption_key)
                encoded = base64.b64encode(encrypted).decode()
                
                # Send to server
                sent = await self.transport.send_message(encoded, "me")
                
                # Show in local log
                timestamp = time.strftime("%H:%M")
                log.write(f"[blue][{timestamp}] You:[/blue] {message}")
                
            except Exception as e:
                log.write(f"[red]✗ Failed to send: {e}[/red]")
        else:
            log.write("[red]✗ No encryption key - cannot send[/red]")
    
    def _on_message_received(self, msg: Message):
        """Handle incoming message from transport"""
        log = self.query_one("#chat-log", RichLog)
        
        if msg.sender == "me":
            return  # Skip our own messages
        
        # Decrypt message
        if self.encryption_key:
            try:
                encrypted = base64.b64decode(msg.content)
                decrypted = decrypt_message(encrypted, self.encryption_key)
                
                if decrypted:
                    timestamp = time.strftime("%H:%M", time.localtime(msg.timestamp))
                    log.write(f"[green][{timestamp}] {msg.sender}:[/green] {decrypted}")
                else:
                    # Try with current key (for rotating mode)
                    if self.room.credentials.mode == "rotating":
                        current_pin = get_current_pin(self.room.credentials)
                        new_key = get_encryption_key(self.room.credentials, current_pin)
                        decrypted = decrypt_message(encrypted, new_key)
                        
                        if decrypted:
                            self.encryption_key = new_key
                            timestamp = time.strftime("%H:%M", time.localtime(msg.timestamp))
                            log.write(f"[green][{timestamp}] {msg.sender}:[/green] {decrypted}")
                        else:
                            log.write("[dim]✗ Could not decrypt message (key mismatch)[/dim]")
                    else:
                        log.write("[dim]✗ Could not decrypt message[/dim]")
            except Exception:
                log.write("[dim]✗ Failed to process message[/dim]")
    
    def _on_state_change(self, state: ConnectionState):
        """Handle connection state changes"""
        status = self.query_one("#conn-status", Static)
        
        status.remove_class("connected", "disconnected", "connecting")
        
        if state == ConnectionState.CONNECTED:
            status.update("● Connected")
            status.add_class("connected")
        elif state == ConnectionState.DISCONNECTED:
            status.update("○ Disconnected")
            status.add_class("disconnected")
        elif state == ConnectionState.CONNECTING:
            status.update("◐ Connecting...")
            status.add_class("connecting")
        elif state == ConnectionState.RECONNECTING:
            status.update("◐ Reconnecting...")
            status.add_class("connecting")
        elif state == ConnectionState.ERROR:
            status.update("✗ Error")
            status.add_class("disconnected")
    
    def _on_members_update(self, members: list[str]):
        """Update member list"""
        members_list = self.query_one("#members-list", VerticalScroll)
        members_list.remove_children()
        
        for member in members:
            members_list.mount(Static(f"• {member}", classes="member"))
    
    def _on_room_expire(self):
        """Handle room expiration"""
        log = self.query_one("#chat-log", RichLog)
        log.write("")
        log.write("[bold red]═══════════════════════════════════════[/bold red]")
        log.write("[bold red]  Room has expired. Chat ended.        [/bold red]")
        log.write("[bold red]  All messages have been wiped.        [/bold red]")
        log.write("[bold red]═══════════════════════════════════════[/bold red]")
        
        # Disable input
        self.query_one("#msg-input", Input).disabled = True
    
    def action_leave(self):
        """Leave the room"""
        self.app.switch_screen(WelcomeScreen())
    
    def action_clear_log(self):
        """Clear chat log"""
        log = self.query_one("#chat-log", RichLog)
        log.clear()


class SOSApp(App):
    """SOS Emergency Secure Chat Application"""
    
    TITLE = "SOS - Emergency Secure Chat"
    CSS = """
    Screen {
        background: #010409;
    }
    """
    
    # Disable mouse support to avoid escape code issues in some terminals
    ENABLE_COMMAND_PALETTE = False
    
    BINDINGS = [
        Binding("ctrl+c", "quit", "Quit", show=False),
        Binding("ctrl+q", "quit", "Quit", show=False),
    ]
    
    def on_mount(self):
        # Disable mouse tracking to prevent escape code issues
        self.mouse_over = None
        self.push_screen(WelcomeScreen())
    
    def action_quit(self):
        self.exit()


def main():
    """Entry point"""
    app = SOSApp()
    app.run()


if __name__ == "__main__":
    main()
