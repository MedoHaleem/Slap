// Use SimplePeer constructor directly from a CDN
// This avoids Node.js built-in module dependencies
const script = document.createElement('script');
script.src = 'https://cdn.jsdelivr.net/npm/simple-peer@9.11.1/simplepeer.min.js';
script.crossOrigin = 'anonymous';
script.onload = () => {
  console.log("SimplePeer library loaded successfully");
  simplePeerLoaded = true;
  // Trigger any pending operations that were waiting for SimplePeer
  if (window.pendingVoiceChatOperations) {
    window.pendingVoiceChatOperations.forEach(callback => callback());
    window.pendingVoiceChatOperations = [];
  }
};
script.onerror = (err) => {
  console.error("Failed to load SimplePeer library:", err);
};
document.head.appendChild(script);

// Track if SimplePeer is already loaded
window.simplePeerLoaded = typeof SimplePeer !== 'undefined';
// This is now handled in the script tag above

export class VoiceChat {
  constructor(initiator = false) {
    this.peer = null;
    this.stream = null;
    this.initiator = initiator;
    this.connected = false;
    this.eventHandlers = {};
    this.pendingSignals = [];
    this.initialized = false;
    this.receivedAnswer = false; // Track if we've already received an answer
    this.audioContext = null;
    this.audioElement = null;
    this.audioAnalysisInterval = null;
    this.audioElementCheckInterval = null;
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
    if (window.simplePeerLoaded) return true;
    
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('SimplePeer library load timeout'));
      }, 10000);
      
      const checkLoaded = () => {
        if (typeof SimplePeer !== 'undefined') {
          clearTimeout(timeout);
          window.simplePeerLoaded = true;
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
      
      try {
        this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      } catch (err) {
        console.error("Microphone access denied:", err);
        this.emit('error', 'Microphone access denied. Please check your permissions.');
        return false;
      }
      
      // Create the peer with config for more reliable connections
      // Cache ICE servers to avoid recreation
      const iceServers = [
        { urls: 'stun:stun.l.google.com:19302' },
        { urls: 'stun:global.stun.twilio.com:3478' },
        {
          urls: 'turn:openrelay.metered.ca:80',
          username: 'openrelayproject',
          credential: 'openrelayproject'
        },
        {
          urls: 'turn:openrelay.metered.ca:443',
          username: 'openrelayproject',
          credential: 'openrelayproject'
        },
        {
          urls: 'turn:openrelay.metered.ca:443?transport=tcp',
          username: 'openrelayproject',
          credential: 'openrelayproject'
        }
      ];

      this.peer = new SimplePeer({
        initiator: this.initiator,
        stream: this.stream,
        trickle: false,
        config: {
          iceServers: iceServers,
          iceCandidatePoolSize: 10,
          iceTransportPolicy: 'all'
        }
      });
      
      this.setupPeerEvents();
      
      // Process any pending signals that were received before initialization
      if (this.pendingSignals.length > 0) {
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
      this.emit('signal', data);
    });

    this.peer.on('connect', () => {
      this.connected = true;
      this.emit('connected');
    });

    this.peer.on('stream', stream => {
      
      // Create audio element for playback
      this.audioElement = document.createElement('audio');
      this.audioElement.autoplay = true;
      this.audioElement.muted = false;
      this.audioElement.srcObject = stream;
      
      // Set volume to maximum and ensure it's not muted
      this.audioElement.volume = 1.0;
      this.audioElement.muted = false;
      
      // Add audio element event listeners
      this.audioElement.onplay = () => console.log("Audio started playing");
      this.audioElement.onpause = () => console.log("Audio paused");
      this.audioElement.onended = () => console.log("Audio ended");
      this.audioElement.onerror = (e) => console.error("Audio error:", e);
      
      // Try to play with user interaction requirement
      const playPromise = this.audioElement.play();
      
      if (playPromise !== undefined) {
        playPromise.then(() => {
          console.log("Audio playing successfully");
        }).catch(err => {
          console.error("Error playing audio:", err);
          
          // Try to play after a user interaction (like a click)
          document.addEventListener('click', function playAudio() {
            this.audioElement.play().then(() => {
              console.log("Audio played after user interaction");
              document.removeEventListener('click', playAudio);
            }).catch(err => {
              console.error("Still failed after user interaction:", err);
            });
          }.bind(this), { once: true });
        });
      }
    });

    this.peer.on('error', err => {
      console.error("Peer connection error:", err);
      this.emit('error', err.message || 'Connection error');
    });

    this.peer.on('close', () => {
      this.connected = false;
      this.emit('disconnected');
      
      // Clean up audio element
      if (this.audioElement) {
        this.audioElement.srcObject = null;
        this.audioElement = null;
      }
      
      // Clean up audio context
      if (this.audioContext) {
        this.audioContext.close();
        this.audioContext = null;
      }
      
      // Clean up audio analysis interval
      if (this.audioAnalysisInterval) {
        clearInterval(this.audioAnalysisInterval);
        this.audioAnalysisInterval = null;
      }
      
      // Clean up audio element check interval
      if (this.audioElementCheckInterval) {
        clearInterval(this.audioElementCheckInterval);
        this.audioElementCheckInterval = null;
      }
    });
    
    // Add ICE connection state change handler
    // Guard against missing _pc (e.g., in environments where SimplePeer doesn't expose it)
    if (this.peer && this.peer._pc) {
      this.peer._pc.addEventListener('iceconnectionstatechange', () => {
        // Check if we're connected but the connect event hasn't fired
        if (this.peer._pc.iceConnectionState === 'connected' && !this.connected) {
          this.connected = true;
          this.emit('connected');
        }
        
        // Handle failed ICE connections
        if (this.peer._pc.iceConnectionState === 'failed') {
          // Try to restart the ICE connection with exponential backoff
          this.restartIceWithBackoff();
        }
      });
    }
  }

  signal(data) {
    try {
      // If not initialized yet, queue the signal
      if (!this.initialized || !this.peer) {
        this.pendingSignals.push(data);
        return;
      }
      
       // Prevent processing multiple answer signals (which causes the state error)
      if (data.type === 'answer' && this.receivedAnswer) {
        return;
      }
      
      // Mark that we've received an answer
      if (data.type === 'answer') {
        this.receivedAnswer = true;
      }
      
      this.peer.signal(data);
    } catch (err) {
      console.error("Error processing signal:", err);
      this.emit('error', 'Error processing signal from peer. Please try again.');
    }
  }

  // Restart ICE with exponential backoff
  restartIceWithBackoff(maxRetries = 3) {
    let retryCount = 0;
    const baseDelay = 1000; // 1 second

    const attemptRestart = () => {
      if (retryCount >= maxRetries || !this.peer || !this.peer._pc) {
        this.emit('error', 'Connection failed after multiple retries. Please check your network connection.');
        return;
      }

      try {
        this.peer._pc.restartIce();
        console.log(`ICE restart attempt ${retryCount + 1} initiated`);
      } catch (err) {
        console.error("Error restarting ICE:", err);
      }

      retryCount++;
      const delay = baseDelay * Math.pow(2, retryCount); // Exponential backoff
      setTimeout(attemptRestart, delay);
    };

    attemptRestart();
  }

  destroy() {
    this.initialized = false;
    this.receivedAnswer = false; // Reset answer flag for next call
    
    if (this.stream) {
      this.stream.getTracks().forEach(track => {
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
    
    // Clean up audio element
    if (this.audioElement) {
      this.audioElement.srcObject = null;
      this.audioElement = null;
    }
    
    // Clean up audio context
    if (this.audioContext) {
      this.audioContext.close();
      this.audioContext = null;
    }
    
    // Clean up audio analysis interval
    if (this.audioAnalysisInterval) {
      clearInterval(this.audioAnalysisInterval);
      this.audioAnalysisInterval = null;
    }
    
    // Clean up audio element check interval
    if (this.audioElementCheckInterval) {
      clearInterval(this.audioElementCheckInterval);
      this.audioElementCheckInterval = null;
    }
  }
} 