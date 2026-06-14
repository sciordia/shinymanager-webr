/* Device-remember cookie bridge for the local (server) variant.
   Exposes the shinymanager_device cookie to Shiny on connect, and lets the
   server set/clear it via custom messages. */
$(function () {
  function getCookie(name) {
    var m = document.cookie.match("(^|;)\\s*" + name + "\\s*=\\s*([^;]+)");
    return m ? m.pop() : "";
  }

  $(document).on("shiny:connected", function () {
    Shiny.setInputValue("shinymanager_device", getCookie("shinymanager_device"));
  });

  Shiny.addCustomMessageHandler("shinymanager_set_device_cookie", function (msg) {
    var maxAge = msg.max_age || 86400;
    document.cookie =
      "shinymanager_device=" + msg.value + ";path=/;max-age=" + maxAge + ";SameSite=Lax";
  });

  Shiny.addCustomMessageHandler("shinymanager_clear_device_cookie", function () {
    document.cookie = "shinymanager_device=;path=/;max-age=0;SameSite=Lax";
  });
});
