// Add cache-busting parameter to ensure fresh version is loaded
import { VoiceChat } from '../components/VoiceChat?v=1.0.1';

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
      console.log("SIGNAL RECEIVED: Received signal from server", from, "type:", signal.type);
      console.log("SIGNAL DETAILS:", JSON.stringify(signal, null, 2));
      
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

    // Function to open voice call window directly from user interaction
    this.openVoiceCallWindow = (url, callId) => {
      try {
        console.log("VOICE_CHAT_HOOK: Opening voice call window directly from user interaction");
        console.log(`VOICE_CHAT_HOOK: Attempting to open window: URL=${url}, CallID=${callId}`); // Debug log
        
        if (!url || !callId) {
          console.error("VOICE_CHAT_HOOK: Missing required parameters for opening voice call window");
          return;
        }
        
        const windowName = `voice_call_${callId || new Date().getTime()}`; // Unique name helps manage windows
        const windowFeatures = "width=450,height=700,resizable=yes,scrollbars=yes,status=yes,noopener,noreferrer";
        const newWindow = window.open(url, windowName, windowFeatures);
        
        if (!newWindow || newWindow.closed || typeof newWindow.closed === 'boolean') {
          console.error("VOICE_CHAT_HOOK: Failed to open voice call window - popup blocker may be blocking it");
          console.log("VOICE_CHAT_HOOK: User interaction context available - popup blocker should allow this");
        } else {
          console.log("VOICE_CHAT_HOOK: Voice call window opened successfully");
        }
      } catch (error) {
        console.error("VOICE_CHAT_HOOK: Error opening voice call window:", error);
      }
    };

    // Fallback event listener for backward compatibility
    window.addEventListener("phx:open_voice_call_window", (e) => {
      console.log("VOICE_CHAT_HOOK: phx:open_voice_call_window event received", e.detail); // Debug log
      const { url, call_id } = e.detail;
      this.openVoiceCallWindow(url, call_id);
    });

    // Handle direct button click for accepting calls (user interaction context)
    this.el.addEventListener('click', (event) => {
      try {
        // Check if this is the accept call button
        if (event.target.matches('button[data-url][data-call-id]') ||
            event.target.closest('button[data-url][data-call-id]')) {
          
          const button = event.target.matches('button[data-url][data-call-id]')
            ? event.target
            : event.target.closest('button[data-url][data-call-id]');
          
          const url = button.dataset.url;
          const callId = button.dataset.callId;
          
          console.log("VOICE_CHAT_HOOK: Direct button click detected");
          console.log(`VOICE_CHAT_HOOK: Button data - URL=${url}, CallID=${callId}`);
          
          // Validate required data
          if (!url || !callId) {
            console.error("VOICE_CHAT_HOOK: Missing required data attributes on button");
            return;
          }
          
          // Call the window opening function directly from user interaction
          this.openVoiceCallWindow(url, callId);
        }
      } catch (error) {
        console.error("VOICE_CHAT_HOOK: Error in button click handler:", error);
      }
    });
    
    // NOTE: Removed conflicting open_voice_chat handler that was causing immediate window closure
    // The openVoiceCallWindow function and direct button click handler should handle window opening
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
    console.log("Voice chat context - userId:", this.userId, "targetId:", this.targetId, "callId:", this.callId);
    console.log("Voice chat initialization - initiator:", initiator, "window open:", !!window.open);
    this.pushEvent('update_status', { status: "connecting" });
    
    // Create a promise we can track
    this.pendingOperation = new Promise(async (resolve) => {
      try {
        // Create VoiceChat instance with only the initiator parameter
        this.voiceChat = new VoiceChat(initiator);
        
        // Set up instance properties
        this.voiceChat.userId = this.userId;
        this.voiceChat.targetId = this.targetId;
        this.voiceChat.callId = this.callId;
        
        // Register event handlers using the on() method
        this.voiceChat.on('statusChange', (status) => {
          console.log("Voice chat status changed:", status);
          this.pushEvent('update_status', { status });
        });
        
        this.voiceChat.on('signal', (signal) => {
          console.log("SIGNAL TO SERVER: Sending signal to server");
          console.log("SIGNAL TO SERVER: Signal type:", signal.type);
          console.log("SIGNAL TO SERVER: Call ID:", this.callId);
          console.log("SIGNAL TO SERVER: User ID:", this.userId);
          console.log("SIGNAL TO SERVER: Target ID:", this.targetId);
          this.pushEvent('signal', { signal });
        });
        
        this.voiceChat.on('connected', () => {
          console.log("CALL CONNECTED: Voice chat connection established successfully!");
          this.pushEvent('update_status', { status: "connected" });
        });
        
        this.voiceChat.on('disconnected', () => {
          console.log("Voice chat disconnected");
          this.pushEvent('update_status', { status: "disconnected" });
          this.voiceChat = null;
        });
        
        this.voiceChat.on('error', (error) => {
          console.error("Voice chat error:", error);
          this.pushEvent('update_status', { status: "error" });
        });

        // Wait for initialization to complete
        await this.voiceChat.init();
        console.log("Voice chat initialized successfully");
        
        // Clear pending operation
        this.pendingOperation = null;
        
        return true;
      } catch (error) {
        console.error("Failed to initialize voice chat:", error);
        this.pushEvent('update_status', { status: "error" });
        this.pendingOperation = null;
        throw error;
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