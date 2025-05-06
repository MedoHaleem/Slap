import { VoiceChat } from '../components/VoiceChat';

export const VoiceChatHook = {
  mounted() {
    this.voiceChat = null;
    this.userId = this.el.dataset.userId;
    this.targetId = this.el.dataset.targetId;
    this.callId = this.el.dataset.callId;
    this.signalHandler = null;
    this.callStatus = "init";
    this.pendingOperation = null;
    this.signalRetries = 0;
    this.maxRetries = 3;
    
    // Listen for signal events from the server
    this.handleEvent('voice:receive_signal', ({ signal, from }) => {
      console.log("Received signal from server", from, "type:", signal.type);
      
      // Don't process our own signals
      if (from.toString() === this.userId) {
        console.log("Ignoring signal from self");
        return;
      }
      
      if (this.voiceChat) {
        try {
          this.voiceChat.signal(signal);
        } catch (err) {
          console.error("Error applying signal:", err);
          this.handleSignalError();
        }
      } else {
        // If we receive a signal but don't have a voice chat instance yet,
        // initialize as a non-initiator
        console.log("Initializing as receiver due to incoming signal");
        this.startCall(false).then(() => {
          // Process the signal once voice chat is initialized
          if (this.voiceChat) {
            try {
              this.voiceChat.signal(signal);
            } catch (err) {
              console.error("Error applying signal after initialization:", err);
              this.handleSignalError();
            }
          }
        });
      }
    });
    
    // Listen for initialization request
    this.handleEvent('voice:initialize', ({ initiator }) => {
      console.log("Initializing voice chat as", initiator ? "initiator" : "receiver");
      this.startCall(initiator);
    });
    
    // Listen for close window event
    this.handleEvent('close_window', () => {
      console.log("Closing window");
      if (this.voiceChat) {
        this.voiceChat.destroy();
        this.voiceChat = null;
      }
      window.close();
    });
  },

  async startCall(initiator = false) {
    // Don't reinitialize if already started
    if (this.voiceChat) {
      console.log("Call already initialized, not starting again");
      return;
    }
    
    // Prevent multiple concurrent initialization attempts
    if (this.pendingOperation) {
      console.log("Operation already pending, waiting...");
      return this.pendingOperation;
    }
    
    console.log("Starting voice chat");
    this.pushEvent('update_status', { status: "connecting" });
    
    // Create a promise we can track
    this.pendingOperation = new Promise(async (resolve) => {
      try {
        this.voiceChat = new VoiceChat(initiator);
        
        // Set up event handlers
        this.voiceChat.on('connected', () => {
          console.log("Call connected successfully");
          this.pushEvent('update_status', { status: 'connected' });
          
          // Play a sound to notify the user
          this.playSound('connected');
          
          // Flash the title bar to get the user's attention
          this.flashTitleBar("Call Connected");
        });
        
        this.voiceChat.on('disconnected', () => {
          console.log("Call disconnected");
          this.pushEvent('update_status', { status: 'disconnected' });
          
          // Play disconnect sound
          this.playSound('disconnected');
        });
        
        this.voiceChat.on('error', (message) => {
          console.error("Voice chat error:", message);
          this.pushEvent('update_status', { status: `error: ${message}` });
          
          // Play error sound
          this.playSound('error');
        });
        
        // Start the peer connection
        const success = await this.voiceChat.init();
        
        if (success) {
          // Set up the signal event handler
          this.signalHandler = (e) => {
            try {
              console.log("Sending signal to server", e.detail.signal.type);
              this.pushEvent('signal', { data: e.detail.signal });
            } catch (err) {
              console.error("Error sending signal:", err);
            }
          };
          
          window.addEventListener('voice:signal', this.signalHandler);
          resolve(true);
        } else {
          console.error("Failed to initialize voice chat");
          this.voiceChat = null;
          this.pushEvent('update_status', { status: 'error: Failed to initialize call' });
          resolve(false);
        }
      } catch (err) {
        console.error("Error in startCall:", err);
        this.pushEvent('update_status', { status: `error: ${err.message || 'Unknown error starting call'}` });
        this.voiceChat = null;
        resolve(false);
      } finally {
        this.pendingOperation = null;
      }
    });
    
    return this.pendingOperation;
  },
  
  handleSignalError() {
    this.signalRetries++;
    
    if (this.signalRetries >= this.maxRetries) {
      console.error("Maximum signal retries reached, giving up");
      this.pushEvent('update_status', { status: 'error: Connection failed after multiple attempts' });
    } else {
      console.log(`Signal error, retry ${this.signalRetries}/${this.maxRetries}`);
    }
  },
  
  flashTitleBar(message) {
    const originalTitle = document.title;
    let titleFlash = setInterval(() => {
      document.title = document.title === originalTitle 
        ? `📞 ${message}` 
        : originalTitle;
    }, 1000);
    
    // Stop flashing after 10 seconds
    setTimeout(() => {
      clearInterval(titleFlash);
      document.title = originalTitle;
    }, 10000);
  },
  
  playSound(type) {
    // Create audio elements for notifications
    const sounds = {
      'connected': 'https://cdn.jsdelivr.net/npm/web-audio-samples@1.0.1/dialog/communication-channel.mp3',
      'disconnected': 'https://cdn.jsdelivr.net/npm/web-audio-samples@1.0.1/dialog/dialog-error.mp3',
      'incoming': 'https://cdn.jsdelivr.net/npm/web-audio-samples@1.0.1/dialog/navigation_forward-selection-minimal.mp3',
      'error': 'https://cdn.jsdelivr.net/npm/web-audio-samples@1.0.1/dialog/dialog-error.mp3'
    };
    
    if (sounds[type]) {
      const audio = new Audio(sounds[type]);
      audio.volume = 0.5;
      audio.play()
        .then(() => console.log(`Playing ${type} sound`))
        .catch(err => console.error(`Error playing ${type} sound:`, err));
    }
  },

  updated() {
    // Check for status changes
    const newStatus = this.el.dataset.callStatus;
    if (newStatus && newStatus !== this.callStatus) {
      this.callStatus = newStatus;
      
      if (newStatus === "incoming") {
        this.playSound('incoming');
        this.flashTitleBar("Incoming Call");
      }
    }
  },

  destroyed() {
    console.log("Voice chat component unmounted");
    if (this.signalHandler) {
      window.removeEventListener('voice:signal', this.signalHandler);
      this.signalHandler = null;
    }
    
    if (this.voiceChat) {
      this.voiceChat.destroy();
      this.voiceChat = null;
    }
  }
}; 