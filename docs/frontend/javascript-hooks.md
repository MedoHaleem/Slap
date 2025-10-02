# JavaScript Hooks

This document provides a comprehensive overview of the JavaScript hooks used in the Slap application to enhance Phoenix LiveView functionality with client-side interactivity.

## Overview

Phoenix LiveView hooks allow you to add client-side JavaScript to specific DOM elements. Hooks are used in Slap for:

- Managing complex UI interactions
- Integrating with third-party libraries
- Handling real-time updates
- Optimizing user experience

## Hook Architecture

### Hook Lifecycle

Each hook follows the Phoenix LiveView hook lifecycle:

1. **mounted()**: Called when the hook is first mounted
2. **updated()**: Called when the hook's assigns are updated
3. **destroyed()**: Called when the hook is removed from the DOM
4. **disconnected()**: Called when the LiveView disconnects
5. **reconnected()**: Called when the LiveView reconnects

### Hook Registration

Hooks are registered in the main LiveSocket:

```javascript
// assets/js/app.js
import ChatMessageTextArea from "./hooks/ChatMessageTextArea";
import RoomMessages from "./hooks/RoomMessages";
import Thread from "./hooks/Thread";
import VoiceChat from "./hooks/voice_chat";

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: {
    ChatMessageTextArea,
    RoomMessages,
    Thread,
    VoiceChat
  }
});
```

## Core Hooks

### ChatMessageTextArea

**Location**: [`assets/js/hooks/ChatMessageTextArea.js`](../../assets/js/hooks/ChatMessageTextArea.js)

Handles auto-resizing text areas for message composition.

#### Features

- Auto-resizes textarea based on content
- Maintains focus during resize
- Handles keyboard shortcuts
- Manages character limits

#### Implementation

```javascript
const ChatMessageTextArea = {
  mounted() {
    this.textarea = this.el.querySelector("textarea");
    this.setupAutoResize();
    this.setupKeyboardShortcuts();
  },

  setupAutoResize() {
    const resize = () => {
      this.textarea.style.height = 'auto';
      this.textarea.style.height = this.textarea.scrollHeight + 'px';
    };

    this.textarea.addEventListener('input', resize);
    
    // Initial resize
    resize();
  },

  setupKeyboardShortcuts() {
    this.textarea.addEventListener('keydown', (e) => {
      // Send message with Ctrl+Enter or Cmd+Enter
      if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
        e.preventDefault();
        this.el.querySelector("button[type='submit']").click();
      }
    });
  },

  updated() {
    // Re-setup after LiveView update
    this.setupAutoResize();
  }
};

export default ChatMessageTextArea;
```

### RoomMessages

**Location**: [`assets/js/hooks/RoomMessages.js`](../../assets/js/hooks/RoomMessages.js)

Manages message list functionality including scrolling and pagination.

#### Features

- Auto-scroll to new messages
- Load more messages on scroll to top
- Maintain scroll position during updates
- Highlight new messages

#### Implementation

```javascript
const RoomMessages = {
  mounted() {
    this.messageContainer = this.el;
    this.setupScrollHandling();
    this.setupNewMessageDetection();
  },

  setupScrollHandling() {
    let lastScrollHeight = 0;
    
    // Handle scroll to top for pagination
    this.messageContainer.addEventListener('scroll', () => {
      if (this.messageContainer.scrollTop === 0) {
        this.pushEvent("load-more-messages", {});
        // Maintain scroll position
        lastScrollHeight = this.messageContainer.scrollHeight;
      }
    });

    // Maintain scroll position after new messages load
    this.handleEvent("messages-loaded", () => {
      const newScrollHeight = this.messageContainer.scrollHeight;
      const heightDifference = newScrollHeight - lastScrollHeight;
      this.messageContainer.scrollTop = heightDifference;
    });
  },

  setupNewMessageDetection() {
    // Auto-scroll to bottom for new messages
    this.handleEvent("new-message", () => {
      // Only scroll if user is already at bottom
      const isAtBottom = this.messageContainer.scrollTop + 
                       this.messageContainer.clientHeight >= 
                       this.messageContainer.scrollHeight - 50;
      
      if (isAtBottom) {
        this.scrollToBottom();
      } else {
        this.showNewMessageIndicator();
      }
    });
  },

  scrollToBottom() {
    this.messageContainer.scrollTop = this.messageContainer.scrollHeight;
  },

  showNewMessageIndicator() {
    // Show "new messages" indicator
    const indicator = document.getElementById("new-messages-indicator");
    if (indicator) {
      indicator.classList.remove("hidden");
    }
  }
};

export default RoomMessages;
```

### Thread

**Location**: [`assets/js/hooks/Thread.js`](../../assets/js/hooks/Thread.js)

Manages message thread functionality with nested replies.

#### Features

- Expand/collapse threads
- Load thread replies
- Highlight active thread
- Handle thread navigation

#### Implementation

```javascript
const Thread = {
  mounted() {
    this.threadContainer = this.el;
    this.setupThreadToggle();
    this.setupReplyHandling();
  },

  setupThreadToggle() {
    const toggleButton = this.el.querySelector(".thread-toggle");
    
    if (toggleButton) {
      toggleButton.addEventListener('click', () => {
        const isExpanded = this.threadContainer.classList.contains('expanded');
        
        if (isExpanded) {
          this.collapseThread();
        } else {
          this.expandThread();
        }
      });
    }
  },

  expandThread() {
    this.threadContainer.classList.add('expanded');
    this.pushEvent("load-thread-replies", {
      message_id: this.threadContainer.dataset.messageId
    });
  },

  collapseThread() {
    this.threadContainer.classList.remove('expanded');
  },

  setupReplyHandling() {
    // Handle new replies in thread
    this.handleEvent("new-reply", ({ reply }) => {
      if (this.threadContainer.dataset.messageId === reply.message_id.toString()) {
        this.addReplyToThread(reply);
      }
    });
  },

  addReplyToThread(reply) {
    const repliesContainer = this.el.querySelector(".thread-replies");
    if (repliesContainer) {
      const replyElement = this.createReplyElement(reply);
      repliesContainer.appendChild(replyElement);
    }
  },

  createReplyElement(reply) {
    const div = document.createElement('div');
    div.className = 'thread-reply';
    div.innerHTML = `
      <div class="reply-header">
        <span class="username">${reply.username}</span>
        <span class="timestamp">${reply.timestamp}</span>
      </div>
      <div class="reply-body">${reply.body}</div>
    `;
    return div;
  }
};

export default Thread;
```

### VoiceChat

**Location**: [`assets/js/hooks/voice_chat.js`](../../assets/js/hooks/voice_chat.js)

Manages WebRTC voice chat functionality.

#### Features

- WebRTC peer connection management
- Audio stream handling
- Call signaling
- Connection state management

#### Implementation

```javascript
const VoiceChat = {
  mounted() {
    this.localStream = null;
    this.remoteStream = null;
    this.peerConnection = null;
    this.callStatus = 'idle';
    
    this.setupEventListeners();
    this.setupPeerConnection();
  },

  setupEventListeners() {
    this.handleEvent("initiate_call", ({ target_user_id }) => {
      this.initiateCall(target_user_id);
    });

    this.handleEvent("accept_call", () => {
      this.acceptCall();
    });

    this.handleEvent("end_call", () => {
      this.endCall();
    });

    this.handleEvent("receive_signal", ({ signal }) => {
      this.handleSignal(signal);
    });

    this.handleEvent("connection_state_changed", ({ state }) => {
      this.updateCallStatus(state);
    });
  },

  setupPeerConnection() {
    this.peerConnection = new RTCPeerConnection({
      iceServers: [
        { urls: "stun:stun.l.google.com:19302" }
      ]
    });

    this.peerConnection.onicecandidate = (event) => {
      if (event.candidate) {
        this.pushEvent("send_signal", {
          signal: {
            type: "ice-candidate",
            candidate: event.candidate
          }
        });
      }
    };

    this.peerConnection.ontrack = (event) => {
      this.remoteStream = event.streams[0];
      this.playRemoteAudio();
    };

    this.peerConnection.onconnectionstatechange = () => {
      this.updateCallStatus(this.peerConnection.connectionState);
    };
  },

  async initiateCall(targetUserId) {
    try {
      this.updateCallStatus('calling');
      
      // Get local media stream
      this.localStream = await navigator.mediaDevices.getUserMedia({ 
        audio: true,
        video: false 
      });
      
      // Add local stream to peer connection
      this.localStream.getTracks().forEach(track => {
        this.peerConnection.addTrack(track, this.localStream);
      });

      // Create and send offer
      const offer = await this.peerConnection.createOffer();
      await this.peerConnection.setLocalDescription(offer);
      
      this.pushEvent("send_signal", {
        target_user_id: targetUserId,
        signal: { type: "offer", sdp: offer.sdp }
      });
    } catch (error) {
      console.error("Error initiating call:", error);
      this.updateCallStatus('error');
    }
  },

  async acceptCall() {
    try {
      this.updateCallStatus('connecting');
      
      // Get local media stream
      this.localStream = await navigator.mediaDevices.getUserMedia({ 
        audio: true,
        video: false 
      });
      
      // Add local stream to peer connection
      this.localStream.getTracks().forEach(track => {
        this.peerConnection.addTrack(track, this.localStream);
      });

      // Create and send answer
      const answer = await this.peerConnection.createAnswer();
      await this.peerConnection.setLocalDescription(answer);
      
      this.pushEvent("send_signal", {
        signal: { type: "answer", sdp: answer.sdp }
      });
    } catch (error) {
      console.error("Error accepting call:", error);
      this.updateCallStatus('error');
    }
  },

  async handleSignal(signal) {
    try {
      if (signal.type === "offer") {
        await this.peerConnection.setRemoteDescription(
          new RTCSessionDescription(signal)
        );
        this.pushEvent("call_accepted", {});
      } else if (signal.type === "answer") {
        await this.peerConnection.setRemoteDescription(
          new RTCSessionDescription(signal)
        );
      } else if (signal.type === "ice-candidate") {
        await this.peerConnection.addIceCandidate(
          new RTCIceCandidate(signal.candidate)
        );
      }
    } catch (error) {
      console.error("Error handling signal:", error);
    }
  },

  endCall() {
    if (this.localStream) {
      this.localStream.getTracks().forEach(track => track.stop());
      this.localStream = null;
    }

    if (this.remoteStream) {
      this.remoteStream.getTracks().forEach(track => track.stop());
      this.remoteStream = null;
    }

    if (this.peerConnection) {
      this.peerConnection.close();
      this.peerConnection = null;
    }

    this.updateCallStatus('ended');
  },

  playRemoteAudio() {
    if (this.remoteStream) {
      const audioElement = document.getElementById("remote-audio");
      if (audioElement) {
        audioElement.srcObject = this.remoteStream;
        audioElement.play().catch(console.error);
      }
    }
  },

  updateCallStatus(status) {
    this.callStatus = status;
    
    // Update UI based on status
    const statusElement = document.getElementById("call-status");
    if (statusElement) {
      statusElement.textContent = this.getStatusText(status);
      statusElement.className = `call-status ${status}`;
    }
  },

  getStatusText(status) {
    const statusMap = {
      'idle': 'Ready',
      'calling': 'Calling...',
      'ringing': 'Ringing...',
      'connecting': 'Connecting...',
      'connected': 'Connected',
      'ended': 'Call Ended',
      'error': 'Error'
    };
    
    return statusMap[status] || status;
  }
};

export default VoiceChat;
```

## Utility Functions

### Message Highlighting

**Location**: [`assets/js/utils/messageHighlight.js`](../../assets/js/utils/messageHighlight.js)

Provides search term highlighting functionality.

```javascript
export function highlightSearchTerms(text, query) {
  if (!query || query.trim() === '') {
    return text;
  }
  
  const terms = query.trim().split(/\s+/);
  let highlightedText = text;
  
  terms.forEach(term => {
    if (term.length > 0) {
      const regex = new RegExp(`(${escapeRegExp(term)})`, 'gi');
      highlightedText = highlightedText.replace(regex, '<mark>$1</mark>');
    }
  });
  
  return highlightedText;
}

function escapeRegExp(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
```

## LiveView Integration

### Hook Usage in Templates

Hooks are attached to DOM elements using the `phx-hook` attribute:

```heex
<div id="message-list" phx-hook="RoomMessages">
  <!-- Message content -->
</div>

<textarea id="message-input" phx-hook="ChatMessageTextArea">
</textarea>

<div id="voice-chat" phx-hook="VoiceChat">
  <!-- Voice chat UI -->
</div>
```

### Event Communication

Hooks communicate with LiveView through events:

```javascript
// Send event to LiveView
this.pushEvent("event_name", { data: "value" });

// Receive event from LiveView
this.handleEvent("event_name", (payload) => {
  // Handle event
});
```

### DOM Manipulation

Hooks can manipulate the DOM directly:

```javascript
// Update element content
this.el.innerHTML = newContent;

// Add/remove classes
this.el.classList.add('active');

// Update attributes
this.el.setAttribute('data-status', 'active');
```

## Performance Considerations

### Event Debouncing

Frequent events are debounced to improve performance:

```javascript
setupSearch() {
  const searchInput = this.el.querySelector('input[name="query"]');
  
  searchInput.addEventListener('input', (e) => {
    clearTimeout(this.timeout);
    
    this.timeout = setTimeout(() => {
      this.pushEvent("search", { query: e.target.value });
    }, 300); // 300ms debounce
  });
}
```

### Memory Management

Hooks properly clean up resources:

```javascript
destroyed() {
  // Clean up event listeners
  if (this.timeout) {
    clearTimeout(this.timeout);
  }
  
  // Clean up media streams
  if (this.localStream) {
    this.localStream.getTracks().forEach(track => track.stop());
  }
}
```

## Error Handling

### Graceful Degradation

Hooks handle errors gracefully:

```javascript
async initiateCall(targetUserId) {
  try {
    // Call initiation logic
  } catch (error) {
    console.error("Error initiating call:", error);
    this.updateCallStatus('error');
    this.showErrorMessage("Failed to start call. Please check your microphone.");
  }
}
```

### Browser Compatibility

Hooks check for browser support:

```javascript
mounted() {
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    this.showErrorMessage("Your browser doesn't support voice calls.");
    return;
  }
  
  // Initialize hook
}
```

## Testing Hooks

### Unit Testing

Hooks can be tested with Jest:

```javascript
import ChatMessageTextArea from './ChatMessageTextArea';

describe('ChatMessageTextArea', () => {
  let hook;
  
  beforeEach(() => {
    hook = {
      el: document.createElement('div'),
      pushEvent: jest.fn(),
      handleEvent: jest.fn()
    };
    
    hook.el.innerHTML = '<textarea></textarea>';
  });
  
  test('auto-resizes textarea', () => {
    ChatMessageTextArea.mounted.call(hook);
    
    const textarea = hook.el.querySelector('textarea');
    textarea.value = 'Long text that should resize';
    textarea.dispatchEvent(new Event('input'));
    
    expect(textarea.style.height).toBe('auto');
  });
});
```

### Integration Testing

Hooks can be tested with Cypress:

```javascript
describe('Voice Chat', () => {
  it('initiates a call', () => {
    cy.visit('/voice/1');
    
    // Mock getUserMedia
    cy.window().then((win) => {
      win.navigator.mediaDevices.getUserMedia = () => 
        Promise.resolve(new MediaStream());
    });
    
    cy.get('[data-testid="call-button"]').click();
    cy.get('[data-testid="call-status"]').should('contain', 'Calling...');
  });
});
```

## Best Practices

### Hook Design

- Keep hooks focused on single responsibilities
- Use descriptive function and variable names
- Handle errors gracefully
- Clean up resources properly

### Performance

- Debounce frequent events
- Avoid unnecessary DOM manipulation
- Use event delegation when possible
- Clean up event listeners

### Security

- Sanitize user input
- Validate data from LiveView
- Use secure WebRTC configurations
- Implement proper error handling

This JavaScript hooks documentation provides a comprehensive overview of the client-side interactivity in the Slap application, making it easier for developers to understand and extend the frontend functionality.