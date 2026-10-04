{ ... }: {
  flake.nixosModules.locale = { ... }: {
    time.timeZone = "Australia/Sydney";

    # Every LC_* category falls back to LANG, which this sets. The installer's
    # stock i18n.extraLocaleSettings block (each LC_* = "en_AU.UTF-8") said the
    # same thing nine more times, so it is gone — add an entry there only for a
    # category that should DIFFER (e.g. LC_TIME = "en_GB.UTF-8").
    i18n.defaultLocale = "en_AU.UTF-8";
  };
}
