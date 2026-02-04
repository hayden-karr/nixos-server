# TODO: Get this working correctly as interacts a bit weird with system zellij
_: {
  programs.zellij = {
    enable = true;
    settings = {
      session_name = "server";
      attach_to_session = true;
      show_startup_tips = false;
    };
  };
}
