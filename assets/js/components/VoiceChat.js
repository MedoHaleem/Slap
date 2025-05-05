// Use SimplePeer constructor directly from a CDN
// This avoids Node.js built-in module dependencies
const script = document.createElement('script');
script.src = 'https://cdn.jsdelivr.net/npm/simple-peer@9.11.1/simplepeer.min.js';
document.head.appendChild(script);

// Track if SimplePeer is already loaded
let simplePeerLoaded = typeof SimplePeer !== 'undefined';
script.onload = () => {
  simplePeerLoaded = true;
  console.log("SimplePeer library loaded successfully");
};

export class VoiceChat {
  constructor(initiator = false) {
    this.peer = null;
    this.stream = null;
    this.initiator = initiator;
    this.connected = false;
    this.eventHandlers = {};
    this.pendingSignals = [];
    this.initialized = false;
  }

  on(event, handler) {
    this.eventHandlers[event] = handler;
  }

  emit(event, data) {
    if (this.eventHandlers[event]) {
      this.eventHandlers[event](data);
    }
  }

  async waitForSimplePeer() {
    if (simplePeerLoaded) return true;
    
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('SimplePeer library load timeout'));
      }, 10000);
      
      const checkLoaded = () => {
        if (typeof SimplePeer !== 'undefined') {
          clearTimeout(timeout);
          simplePeerLoaded = true;
          resolve(true);
        } else {
          setTimeout(checkLoaded, 100);
        }
      };
      
      checkLoaded();
    });
  }

  async init() {
    try {
      // Make sure SimplePeer is loaded
      await this.waitForSimplePeer();
      
      console.log("Requesting microphone access...");
      try {
        this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        console.log("Microphone access granted");
      } catch (err) {
        console.error("Microphone access denied:", err);
        this.emit('error', 'Microphone access denied. Please check your permissions.');
        return false;
      }
      
      console.log("Initializing peer connection as", this.initiator ? "initiator" : "receiver");
      
      // Create the peer with config for more reliable connections
      this.peer = new SimplePeer({
        initiator: this.initiator,
        stream: this.stream,
        trickle: false,
        config: {
          iceServers: [
            { urls: 'stun:stun.l.google.com:19302' },
            { urls: 'stun:global.stun.twilio.com:3478' }
          ]
        }
      });
      
      this.setupPeerEvents();
      
      // Process any pending signals that were received before initialization
      if (this.pendingSignals.length > 0) {
        console.log(`Processing ${this.pendingSignals.length} pending signals`);
        this.pendingSignals.forEach(signal => {
          try {
            this.peer.signal(signal);
          } catch (err) {
            console.error("Error processing pending signal:", err);
          }
        });
        this.pendingSignals = [];
      }
      
      this.initialized = true;
      return true;
    } catch (err) {
      console.error('Failed to initialize voice chat:', err);
      this.emit('error', err.message || 'Failed to initialize voice chat');
      return false;
    }
  }

  setupPeerEvents() {
    this.peer.on('signal', data => {
      console.log("Signal generated, sending to peer:", data.type);
      window.dispatchEvent(new CustomEvent('voice:signal', {
        detail: { signal: data }
      }));
    });

    this.peer.on('connect', () => {
      console.log("Peer connection established");
      this.connected = true;
      this.emit('connected');
    });

    this.peer.on('stream', stream => {
      console.log("Received audio stream from peer");
      const audio = new Audio();
      audio.srcObject = stream;
      audio.play()
        .then(() => console.log("Audio playing"))
        .catch(err => console.error("Error playing audio:", err));
    });

    this.peer.on('error', err => {
      console.error("Peer connection error:", err);
      this.emit('error', err.message || 'Connection error');
    });

    this.peer.on('close', () => {
      console.log("Peer connection closed");
      this.connected = false;
      this.emit('disconnected');
    });
    
    // Add debug logging for ICE events
    this.peer._pc.addEventListener('iceconnectionstatechange', () => {
      console.log('ICE connection state:', this.peer._pc.iceConnectionState);
      
      // Handle failed ICE connections
      if (this.peer._pc.iceConnectionState === 'failed') {
        this.emit('error', 'Connection failed. Please try again.');
      }
    });
  }

  signal(data) {
    try {
      console.log("Received signal from peer, type:", data.type);
      
      // If not initialized yet, queue the signal
      if (!this.initialized || !this.peer) {
        console.log("Peer not ready, queueing signal");
        this.pendingSignals.push(data);
        return;
      }
      
      this.peer.signal(data);
    } catch (err) {
      console.error("Error processing signal:", err);
      this.emit('error', 'Error processing signal from peer. Please try again.');
    }
  }

  destroy() {
    console.log("Destroying voice chat");
    this.initialized = false;
    
    if (this.stream) {
      this.stream.getTracks().forEach(track => {
        console.log("Stopping track:", track.kind);
        track.stop();
      });
      this.stream = null;
    }
    
    if (this.peer) {
      this.peer.destroy();
      this.peer = null;
    }
    
    this.connected = false;
    this.emit('disconnected');
  }
} 