const Thread = {
  mounted() {
    const messageAndReplies = this.el.querySelector(
      "#thread-message-with-replies"
    );
    messageAndReplies.scrollTop = messageAndReplies.scrollHeight;

    this.handleEvent("scroll_thread_to_bottom", () => {
      messageAndReplies.scrollTop = messageAndReplies.scrollHeight;
    });

    this.handleEvent("update_avatar", ({ user_id, avatar_path }) => {
      const avatars = this.el.querySelectorAll(
        `img[data-user-avatar-id="${user_id}"]`
      );

      avatars.forEach(function (avatar) {
        avatar.src = `/uploads/${avatar_path}`;
      });
    });

    this.handleEvent("highlight_thread_message", ({ message_id }) => {
      const messageElement = this.el.querySelector(`[data-message-id="${message_id}"]`);
      if (messageElement) {
        // Add the highlight class
        messageElement.classList.add('thread-highlight', 'message-highlight-animation');
        
        // Remove animation class after animation completes
        setTimeout(() => {
          messageElement.classList.remove('message-highlight-animation');
        }, 3000);
        
        // Scroll to the highlighted message
        messageElement.scrollIntoView({
          behavior: 'smooth',
          block: 'center'
        });
      }
    });
  },
};

export default Thread;
