{ inputs, ... }: {
  flake.nixosModules.sddm = { pkgs, lib, ... }: let
    background = ./pixel-emerald.mp4;
    backgroundName = builtins.baseNameOf background;
  in {
    imports = [ inputs.silentSDDM.nixosModules.default ];

    programs.silentSDDM = {
      enable = true;
      theme = "default";

      backgrounds = {
        "${backgroundName}" = background;
      };

      settings = {
        General = {
          background-fill-mode = "fill";
          enable-animations = true;
        };
        LockScreen = {
          background = backgroundName;
          blur = 0;
          brightness = -0.1;
          saturation = 0.1;
        };
        "LockScreen.Clock" = {
          position = "top-left";
          align = "left";
          format = "hh:mm ap";
          font-family = "JetBrainsMono Nerd Font";
          font-size = 120;
          font-weight = 900;
          color = "#a8d8a8";
        };
        "LockScreen.Date" = {
          format = "dddd, MMMM dd, yyyy";
          locale = "en_AU";
          font-family = "JetBrainsMono Nerd Font";
          font-size = 18;
          font-weight = 400;
          color = "#7ab87a";
          margin-top = -10;
        };
        "LockScreen.Message".display = false;
        LoginScreen = {
          background = backgroundName;
          blur = 0;
          brightness = -0.1;
          saturation = 0.1;
        };
        "LoginScreen.LoginArea" = {
          position = "left";
          margin = 80;
        };
        "LoginScreen.LoginArea.Avatar" = {
          active-size = 0;
          inactive-size = 0;
          active-border-size = 0;
          inactive-border-size = 0;
        };
        "LoginScreen.LoginArea.Username" = {
          font-family = "JetBrainsMono Nerd Font";
          font-size = 18;
          font-weight = 700;
          color = "#a8d8a8";
          margin = 10;
        };
        "LoginScreen.LoginArea.PasswordInput" = {
          width = 250;
          height = 35;
          display-icon = true;
          font-family = "JetBrainsMono Nerd Font";
          font-size = 13;
          content-color = "#a8d8a8";
          background-color = "#0d1f0d";
          background-opacity = 0.8;
          border-size = 2;
          border-color = "#4a7c4a";
          border-radius-left = 8;
          border-radius-right = 0;
          margin-top = 12;
        };
        "LoginScreen.LoginArea.LoginButton" = {
          background-color = "#4a7c4a";
          background-opacity = 0.0;
          active-background-color = "#4a7c4a";
          active-background-opacity = 1.0;
          content-color = "#a8d8a8";
          active-content-color = "#0d1f0d";
          border-size = 2;
          border-color = "#4a7c4a";
          border-radius-left = 0;
          border-radius-right = 8;
          margin-left = 0;
          hide-if-not-needed = true;
        };
        "LoginScreen.LoginArea.Spinner" = {
          color = "#a8d8a8";
          font-family = "JetBrainsMono Nerd Font";
        };
        "LoginScreen.LoginArea.WarningMessage" = {
          font-family = "JetBrainsMono Nerd Font";
          font-size = 11;
          normal-color = "#7ab87a";
          warning-color = "#d4a843";
          error-color = "#c75e5e";
          margin-top = 8;
        };
        "LoginScreen.MenuArea.Buttons" = {
          margin-bottom = 40;
          margin-left = 80;
          size = 22;
          spacing = 10;
        };
        "LoginScreen.MenuArea.Popups" = {
          background-color = "#0d1f0d";
          background-opacity = 0.95;
          content-color = "#a8d8a8";
          active-option-background-color = "#4a7c4a";
          active-option-background-opacity = 1.0;
          active-content-color = "#0d1f0d";
          border-size = 1;
          border-color = "#4a7c4a";
          font-family = "JetBrainsMono Nerd Font";
        };
        "LoginScreen.MenuArea.Session" = {
          position = "bottom-left";
          index = 1;
          content-color = "#a8d8a8";
          border-size = 0;
          display-session-name = true;
        };
        "LoginScreen.MenuArea.Layout" = {
          position = "bottom-left";
          index = 2;
          content-color = "#a8d8a8";
          border-size = 0;
        };
        "LoginScreen.MenuArea.Keyboard" = {
          position = "bottom-left";
          index = 3;
          content-color = "#a8d8a8";
          border-size = 0;
        };
        "LoginScreen.MenuArea.Power" = {
          position = "bottom-left";
          index = 4;
          content-color = "#a8d8a8";
          border-size = 0;
        };
        "LoginScreen.VirtualKeyboard" = {
          start-hidden = true;
          background-color = "#0d1f0d";
          background-opacity = 0.95;
          key-content-color = "#a8d8a8";
          key-color = "#1a3d1a";
          key-opacity = 1.0;
          border-size = 1;
          border-color = "#4a7c4a";
          primary-color = "#a8d8a8";
        };
        Tooltips = {
          background-color = "#0d1f0d";
          background-opacity = 0.95;
          content-color = "#a8d8a8";
          border-radius = 5;
        };
      };
    };
  };
}
