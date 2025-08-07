const script = document.createElement('script');
script.src = 'https://cdn.jsdelivr.net/npm/simple-peer@9.11.1/simplepeer.min.js';
script.crossOrigin = 'anonymous';
document.head.appendChild(script);

export class VoiceChat {
  constructor(initiator = false) {
    this.peer = null;
    this.stream = null;
    this.initiator = initiator;
    this.connected = false;
    this.eventHandlers = {};
    this.pendingSignals = [];
    this.initialized = false;
    this.receivedAnswer = false;
  }

  on(event, handler) {
    this.eventHandlers[event] = handler;
  }

  emit(event, data) {
    if (this.eventHandlers[event]) {
      this.eventHandlers[event](data);
    }
  }

  async init() {
    try {
      if (typeof SimplePeer === 'undefined') {
        await new Promise(resolve => {
          const check = () => {
            if (typeof SimplePeer !== 'undefined') resolve();
            else setTimeout(check, 100);
          };
          check();
        });
      }

      try {
        this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      } catch {
        this.emit('error', 'Microphone access denied');
        return false;
      }

      const iceServers = [
        { urls: 'stun:stun.l.google.com:19302' },
        { urls: 'stun:global.stun.twilio.com:3478' },
        { urls: 'turn:openrelay.metered.ca:80', username: 'openrelayproject', credential: 'openrelayproject' },
        { urls: 'turn:openrelay.metered.ca:443', username: 'openrelayproject', credential: 'openrelayproject' },
        { urls: 'turn:openrelay.metered.ca:443?transport=tcp', username: 'openrelayproject', credential: 'openrelayproject' }
      ];

      this.peer = new SimplePeer({
        initiator: this.initiator,
        stream: this.stream,
        config: { iceServers }
      });

      this.setupPeerEvents();
      this.processPendingSignals();
      this.initialized = true;
      return true;
    } catch (err) {
      this.emit('error', 'Failed to initialize voice chat');
      return false;
    }
  }

  setupPeerEvents() {
    this.peer.on('signal', data => this.emit('signal', data));
    this.peer.on('connect', () => {
      this.connected = true;
      this.emit('connected');
    });
    this.peer.on('stream', stream => this.handleStream(stream));
    this.peer.on('error', err => this.emit('error', err.message));
    this.peer.on('close', () => this.cleanup());
  }

  handleStream(stream) {
    const audio = document.createElement('audio');
    audio.autoplay = true;
    audio.srcObject = stream;
    audio.play().catch(() => {
      document.addEventListener('click', () => audio.play(), { once: true });
    });
    this.audioElement = audio;
  }

  processPendingSignals() {
    this.pendingSignals.forEach(signal => {
      try {
        this.peer.signal(signal);
      } catch {}
    });
    this.pendingSignals = [];
  }

  signal(data) {
    if (!this.initialized) {
      this.pendingSignals.push(data);
      return;
    }
    try {
      this.peer.signal(data);
    } catch {
      this.emit('error', 'Error processing signal');
    }
  }

  cleanup() {
    this.connected = false;
    this.emit('disconnected');
    
    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop());
      this.stream = null;
    }
    
    if (this.audioElement) {
      this.audioElement.srcObject = null;
      this.audioElement = null;
    }
    
    if (this.peer) {
      this.peer.destroy();
      this.peer = null;
    }
  }
}