/**
 * Shared message highlighting utility
 * Centralizes message highlighting logic across all hooks
 */

export const highlightMessage = (id, options = {}) => {
  const {
    scrollToView = true,
    highlightClass = 'highlight',
    removeHighlightClass = 'no-highlight',
    duration = 3000
  } = options;

  const messageElement = document.getElementById(`messages-${id}`);
  if (!messageElement) return false;

  // Add highlight class
  messageElement.classList.add(highlightClass);
  
  // Scroll to message if requested
  if (scrollToView) {
    messageElement.scrollIntoView({
      behavior: 'smooth',
      block: 'center'
    });
  }
  
  // Remove highlight after animation
  setTimeout(() => {
    messageElement.classList.remove(highlightClass);
    if (removeHighlightClass) {
      messageElement.classList.add(removeHighlightClass);
    }
  }, duration);
  
  return true;
};

export const retryHighlightMessage = (id, options = {}) => {
  // Try immediate highlight
  if (highlightMessage(id, options)) {
    return Promise.resolve(true);
  }
  
  // If not found, wait and retry
  return new Promise((resolve) => {
    setTimeout(() => {
      const result = highlightMessage(id, options);
      resolve(result);
    }, 100);
  });
};

export default { highlightMessage, retryHighlightMessage };