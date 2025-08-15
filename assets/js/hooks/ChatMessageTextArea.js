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
  }
}
