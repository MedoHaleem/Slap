# Voice Chat System

This document provides a comprehensive overview of the voice chat functionality in Slap, including WebRTC implementation, signaling, and call management.

## Overview

The voice chat system allows users to:

- Initiate voice calls with other users
- Receive call requests and notifications
- Accept or reject incoming calls
- Participate in real-time voice conversations
- Manage call status and connections

## Architecture

### Technology Stack

The voice chat system is built with:

- **WebRTC**: Peer-to-peer audio communication
- **Phoenix Channels**: Signaling server for call setup
- **JavaScript Hooks**: Client-side WebRTC management
- **Phoenix LiveView**: UI and state management

### Components

- [`SlapWeb.VoiceChatLive`](../../lib/slap_web/live/voice_chat_live.ex) - Voice chat LiveView
- [`VoiceChat.js`](../../assets/js/components/VoiceChat.js) - WebRTC JavaScript component
- [`voice_chat.js`](../../assets/js/hooks/voice_chat.js) - Phoenix Hook for voice chat
- Phoenix Channels for signaling

## WebRTC Implementation

### Connection Flow

1. **Call Initiation**: User initiates a call to another user
2. **Signaling**: Call request sent via Phoenix Channels
3. **Offer/Answer**: WebRTC offer/answer exchange
4. **ICE Candidates**: Network information exchange
5. **Connection**: Peer-to-peer audio connection established
6. **Communication**: Real-time audio streaming

### WebRTC Configuration

```javascript
// WebRTC peer connection configuration
const configuration = {
  iceServers: [
    { urls: "stun:stun.l.google.com:19302" },
    // Add additional STUN/TURN servers for production
  ]
};

const peerConnection = new RTCPeerConnection(configuration);
```

### Media Stream Setup

```javascript
// Get user media (microphone)
async function getLocalStream() {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ 
      audio: true,
      video: false 
    });
    return stream;
  } catch (error) {
    console.error("Error accessing microphone:", error);
    throw error;
  }
}
```

## Signaling System

### Phoenix Channels

The signaling system uses Phoenix Channels to coordinate call setup:

```elixir
# Channel definition
defmodule SlapWeb.VoiceChannel do
  use Phoenix.Channel

  def join("voice:" <> user_id, _params, socket) do
    if socket.assigns.current_user.id == String.to_integer(user_id) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("call_request", %{"target_user_id" => target_id}, socket) do
    # Forward call request to target user
    Phoenix.PubSub.broadcast(
      Slap.PubSub,
      "voice:#{target_id}",
      {:voice_call_request, %{caller_id: socket.assigns.current_user.id}}
    )
    {:noreply, socket}
  end
end
```

### Call States

The system tracks several call states:

- **idle**: No active call
- **calling**: Initiating a call
- **ringing**: Call is ringing for recipient
- **connecting**: Call is being established
- **connected**: Active call in progress
- **ended**: Call has ended

## VoiceChatLive Component

### State Management

```elixir
defmodule SlapWeb.VoiceChatLive do
  use Phoenix.LiveView

  def mount(%{"target_user_id" => target_user_id_param}, _session, socket) do
    target_user_id = String.to_integer(target_user_id_param)
    
    socket =
      socket
      |> assign(:current_user, socket.assigns.current_user)
      |> assign(:target_user_id, target_user_id)
      |> assign(:call_status, :idle)
      |> assign(:local_stream, nil)
      |> assign(:remote_stream, nil)
      |> assign(:error_message, nil)
      |> setup_voice_channel()
    
    {:ok, socket}
  end
```

### Event Handling

```elixir
def handle_event("request_call", _, socket) do
  target_user_id = socket.assigns.target_user_id
  
  # Send call request via PubSub
  Phoenix.PubSub.broadcast(
    Slap.PubSub,
    "voice:#{target_user_id}",
    {:voice_call_request, %{caller_id: socket.assigns.current_user.id}}
  )
  
  socket =
    socket
    |> assign(:call_status, :calling)
    |> push_event("initiate_call", %{target_user_id: target_user_id})
  
  {:noreply, socket}
end

def handle_event("accept_call", _, socket) do
  socket =
    socket
    |> assign(:call_status, :connecting)
    |> push_event("accept_call", %{})
  
  {:noreply, socket}
end

def handle_event("reject_call", _, socket) do
  Phoenix.PubSub.broadcast(
    Slap.PubSub,
    "voice:#{socket.assigns.target_user_id}",
    {:call_rejected, %{user_id: socket.assigns.current_user.id}}
  )
  
  socket =
    socket
    |> assign(:call_status, :ended)
    |> push_event("end_call", %{})
  
  {:noreply, socket}
end
```

### Signaling Message Handling

```elixir
def handle_info(%{event: "voice_signal", payload: payload}, socket) do
  socket = push_event(socket, "receive_signal", payload)
  {:noreply, socket}
end

def handle_info(%{event: "voice_call_request", payload: payload}, socket) do
  socket =
    socket
    |> assign(:call_status, :ringing)
    |> assign(:caller_id, payload.caller_id)
  
  {:noreply, socket}
end
```

## JavaScript Implementation

### VoiceChat Hook

```javascript
// assets/js/hooks/voice_chat.js
const VoiceChat = {
  mounted() {
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
  },

  async initiateCall(targetUserId) {
    try {
      // Get local media stream
      this.localStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      
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
    }
  },

  async acceptCall() {
    try {
      // Get local media stream
      this.localStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      
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

  setupPeerConnection() {
    this.peerConnection = new RTCPeerConnection({
      iceServers: [{ urls: "stun:stun.l.google.com:19302" }]
    });

    // Handle ICE candidates
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

    // Handle remote stream
    this.peerConnection.ontrack = (event) => {
      this.remoteStream = event.streams[0];
      this.el.querySelector("#remote-audio").srcObject = this.remoteStream;
    };

    // Handle connection state changes
    this.peerConnection.onconnectionstatechange = () => {
      const state = this.peerConnection.connectionState;
      this.pushEvent("connection_state_changed", { state });
    };
  }
};

export default VoiceChat;
```

### VoiceChat Component

```javascript
// assets/js/components/VoiceChat.js
export class VoiceChat {
  constructor() {
    this.localStream = null;
    this.remoteStream = null;
    this.peerConnection = null;
    this.callStatus = "idle";
  }

  async initialize() {
    await this.setupPeerConnection();
    this.setupEventListeners();
  }

  async setupPeerConnection() {
    this.peerConnection = new RTCPeerConnection({
      iceServers: [
        { urls: "stun:stun.l.google.com:19302" }
      ]
    });

    this.peerConnection.onicecandidate = (event) => {
      if (event.candidate) {
        this.sendSignal({
          type: "ice-candidate",
          candidate: event.candidate
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
  }

  async getLocalMedia() {
    try {
      this.localStream = await navigator.mediaDevices.getUserMedia({
        audio: true,
        video: false
      });
      return this.localStream;
    } catch (error) {
      console.error("Error accessing media devices:", error);
      throw error;
    }
  }

  async createOffer() {
    const offer = await this.peerConnection.createOffer();
    await this.peerConnection.setLocalDescription(offer);
    return offer;
  }

  async createAnswer(offer) {
    await this.peerConnection.setRemoteDescription(offer);
    const answer = await this.peerConnection.createAnswer();
    await this.peerConnection.setLocalDescription(answer);
    return answer;
  }

  async handleRemoteDescription(description) {
    await this.peerConnection.setRemoteDescription(description);
  }

  async handleIceCandidate(candidate) {
    await this.peerConnection.addIceCandidate(candidate);
  }

  playRemoteAudio() {
    if (this.remoteStream) {
      const audioElement = document.getElementById("remote-audio");
      if (audioElement) {
        audioElement.srcObject = this.remoteStream;
        audioElement.play().catch(console.error);
      }
    }
  }

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

    this.callStatus = "ended";
  }
}
```

## User Interface

### Call Status Display

The UI shows different states based on call status:

```elixir
defp call_status_badge(assigns) do
  ~H"""
  <div class={[
    "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium",
    @call_status == "connected" && "bg-green-100 text-green-800",
    @call_status == "calling" && "bg-yellow-100 text-yellow-800",
    @call_status == "ringing" && "bg-blue-100 text-blue-800",
    @call_status == "ended" && "bg-gray-100 text-gray-800"
  ]}>
    <%= status_message(@call_status) %>
  </div>
  """
end

defp status_message(status) do
  case status do
    "idle" -> "Ready"
    "calling" -> "Calling..."
    "ringing" -> "Ringing..."
    "connecting" -> "Connecting..."
    "connected" -> "Connected"
    "ended" -> "Call Ended"
  end
end
```

### Action Buttons

```elixir
defp call_controls(assigns) do
  ~H"""
  <div class="flex space-x-2">
    <%= if @call_status == "idle" do %>
      <button phx-click="request_call" class="bg-green-500 hover:bg-green-600 text-white px-4 py-2 rounded">
        Start Call
      </button>
    <% end %>

    <%= if @call_status == "ringing" do %>
      <button phx-click="accept_call" class="bg-green-500 hover:bg-green-600 text-white px-4 py-2 rounded">
        Accept
      </button>
      <button phx-click="reject_call" class="bg-red-500 hover:bg-red-600 text-white px-4 py-2 rounded">
        Reject
      </button>
    <% end %>

    <%= if @call_status == "connected" do %>
      <button phx-click="end_call" class="bg-red-500 hover:bg-red-600 text-white px-4 py-2 rounded">
        End Call
      </button>
    <% end %>
  </div>
  """
end
```

## Integration with Chat System

### Call Initiation from Chat

Users can initiate voice calls from the chat interface:

```elixir
# In ChatRoomLive
def handle_event("start-voice-call", %{"user-id" => user_id}, socket) do
  {:noreply, 
   socket
   |> push_navigate(to: "/voice/#{user_id}")}
end
```

### Call Notifications

Incoming call requests are displayed as notifications:

```elixir
def handle_info({:voice_call_request, payload}, socket) do
  socket =
    socket
    |> put_flash(:info, "Incoming call from user #{payload.caller_id}")
    |> push_event("show_call_notification", payload)
  
  {:noreply, socket}
end
```

## Error Handling

### Common Error Scenarios

1. **Media Access Denied**: User denies microphone access
2. **Connection Failed**: WebRTC connection cannot be established
3. **ICE Failed**: No network path between peers
4. **User Unavailable**: Target user is offline or busy

### Error Display

```elixir
defp error_message(assigns) do
  ~H"""
  <%= if @error_message do %>
    <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
      <strong>Error:</strong> <%= @error_message %>
    </div>
  <% end %>
  """
end
```

## Security Considerations

### Media Permissions

- Explicit user permission required for microphone access
- Secure context (HTTPS) required for WebRTC
- Permission state properly managed

### Signaling Security

- Authentication required for channel access
- Call requests validated server-side
- User presence verification

### Network Security

- STUN servers for NAT traversal
- TURN servers for relay (production)
- Secure signaling channel

## Browser Compatibility

### Supported Browsers

- Chrome 60+
- Firefox 55+
- Safari 11+
- Edge 79+

### Feature Detection

```javascript
function checkWebRTCSupport() {
  return !!(navigator.mediaDevices && 
           navigator.mediaDevices.getUserMedia && 
           window.RTCPeerConnection);
}
```

## Performance Considerations

### Bandwidth Usage

- Audio-only calls (no video)
- Adaptive bitrate codecs
- Efficient audio compression

### CPU Usage

- WebRTC hardware acceleration
- Efficient audio processing
- Minimal impact on chat performance

## Testing

### Unit Tests

```elixir
defmodule SlapWeb.VoiceChatLiveTest do
  use SlapWeb.ConnCase

  test "mounts voice chat with target user", %{conn: conn} do
    user = user_fixture()
    target_user = user_fixture()
    
    {:ok, _view, html} = live(conn, "/voice/#{target_user.id}")
    
    assert html =~ "Voice Call"
    assert html =~ target_user.username
  end
end
```

### Integration Tests

- End-to-end call flow testing
- Signaling message validation
- Error scenario handling

## Future Enhancements

### Planned Features

- Video calling support
- Group voice calls
- Call recording
- Screen sharing
- Call quality metrics
- Push notifications for incoming calls

### Technical Improvements

- TURN server integration
- Adaptive bitrate streaming
- Echo cancellation
- Noise reduction
- Connection quality monitoring

This voice chat system provides a solid foundation for real-time audio communication with proper error handling and user experience considerations.