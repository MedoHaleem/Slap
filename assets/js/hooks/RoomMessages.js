import { init, Picker } from "emoji-mart";
import data from "@emoji-mart/data";

init({ data });

const RoomMessages = {
  mounted() {
    this.el.scrollTop = this.el.scrollHeight;
    this.handleEvent("scroll_messages_to_bottom", () => {
      this.el.scrollTop = this.el.scrollHeight;
    });

    this.canLoadMore = true;

    this.el.addEventListener("scroll", (e) => {
      if (this.canLoadMore && this.el.scrollTop < 100) {
        const prevHeight = this.el.scrollHeight;
        this.canLoadMore = false;

        this.pushEvent("load-more-messages", {}, (reply) => {
          this.el.scrollTo(0, this.el.scrollHeight - prevHeight);
          this.canLoadMore = reply.can_load_more;
        });
      }
    });

    this.handleEvent("reset_pagination", ({ can_load_more }) => {
      this.canLoadMore = can_load_more;
    });

    this.handleEvent("show_chat_messages", () => {
      // Trigger a re-render of the message list
      this.el.dispatchEvent(new Event('phx:update'));
    });
    this.handleEvent("update_avatar", ({ user_id, avatar_path }) => {
      const avatars = this.el.querySelectorAll(
        `img[data-user-avatar-id="${user_id}"]`
      );

      avatars.forEach(function (avatar) {
        avatar.src = `/uploads/${avatar_path}`;
      });
    });

    this.handleEvent("highlight_message", ({ id }) => {
      const item = document.getElementById(`messages-${id}`);
      if (item) {
        item.classList.add('highlight');
        setTimeout(() => {
          item.classList.remove('highlight');
          item.classList.add('no-highlight');
        }, 3000);
      }
    });


    this.el.addEventListener("show_emoji_picker", (e) => {
      const picker = new Picker({
        onClickOutside: () => this.closePicker(),
        onEmojiSelect: (selection) => {
          this.pushEvent("add-reaction", {
            emoji: selection.native,
            message_id: e.detail.message_id,
          });

          this.closePicker()
        }
      });
      picker.id = "emoji-picker";
      const wrapper = document.getElementById("emoji-picker-wrapper");
      wrapper.appendChild(picker)

      const message = document.getElementById(`messages-${e.detail.message_id}`)
      const rect = message.getBoundingClientRect();

      if (rect.top + wrapper.clientHeight > window.innerHeight) {
        wrapper.style.bottom = `20px`;
      } else {
        wrapper.style.top = `${rect.top}px`;
      }
      wrapper.style.right = '50px';
    });
  },

  closePicker() {
    const picker = document.getElementById("emoji-picker");
    if (picker) {
      picker.parentNode.removeChild(picker);
    }
  },
};

export default RoomMessages;
