export default {
  mounted() {
    this.handleEvent("show_chat_messages", () => {
      const messageList = document.getElementById("room-messages");
      if (messageList) {
        messageList.style.display = "flex";
      }
      const searchResults = document.querySelector(".search-results-container");
      if (searchResults) {
        searchResults.style.display = "none";
      }
    });

    // Handle search input focus and blur events
    const searchInput = document.querySelector('input[name="query"]');
    if (searchInput) {
      searchInput.addEventListener('focus', () => {
        searchInput.parentElement.classList.add('ring-2', 'ring-blue-500');
      });

      searchInput.addEventListener('blur', () => {
        searchInput.parentElement.classList.remove('ring-2', 'ring-blue-500');
      });

      // Add search input debounce for better performance
      let searchTimeout;
      searchInput.addEventListener('input', (e) => {
        clearTimeout(searchTimeout);
        searchTimeout = setTimeout(() => {
          const form = searchInput.closest('form');
          if (form && e.target.value.length > 2) {
            form.dispatchEvent(new Event('submit', { cancelable: true }));
          }
        }, 300);
      });
    }

    // Handle scroll to message functionality
    this.handleEvent("scroll-to-message", (event) => {
      const messageId = event.detail;
      const messageElement = document.getElementById(`messages-${messageId}`);
      if (messageElement) {
        // Scroll the message into view with smooth scrolling
        messageElement.scrollIntoView({
          behavior: 'smooth',
          block: 'center'
        });
        
        // Add a temporary highlight effect
        messageElement.classList.add('bg-yellow-200', 'transition-colors');
        setTimeout(() => {
          messageElement.classList.remove('bg-yellow-200');
        }, 2000);
      }
    });
  },

  updated() {
    // Auto-focus search input when search results are shown
    const searchInput = document.querySelector('input[name="query"]');
    if (searchInput && document.querySelector('.search-results-container')) {
      searchInput.focus();
    }
  }
}
