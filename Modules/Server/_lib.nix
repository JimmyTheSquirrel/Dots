# Shell helpers shared by the Asgard server units — a plain function, imported
# by path (`import ./_lib.nix { inherit pkgs; }`). The leading underscore keeps
# import-tree from treating it as a flake-parts module.
{ pkgs, ... }:
{
  # waitForHttp — a shell snippet that polls an HTTP endpoint until it answers
  # (any status curl -f accepts, i.e. < 400) and EXITS 1 WITH A MESSAGE if it
  # never does.
  #
  # Replaces nine hand-copied `for i in $(seq …); do curl … && break; sleep …;
  # done` loops, most of which simply fell out of the bottom on timeout and let
  # the script carry on against a service that was not there — which then
  # failed somewhere further down with an error that pointed at the wrong thing,
  # or "succeeded" having done nothing. Failing here names the real cause.
  #
  #   name      — what to call it in the log ("Jellyseerr")
  #   url       — spliced inside double quotes, so shell variables expand
  #               ("$SEERR/api/v1/status"); must not itself contain a `"`
  #   tries     — attempts before giving up
  #   interval  — seconds between attempts
  #   curlArgs  — extra curl arguments as shell words, e.g. an auth header
  #               ''-H "X-Api-Key: $SK"''
  #
  # Uses explicit `exit 1` rather than leaning on `set -e`, so it behaves the
  # same in the best-effort scripts that run under `set +e`.
  waitForHttp = { name, url, tries ? 60, interval ? 2, curlArgs ? "" }: ''
    __wait_ok=0
    for __wait_i in $(${pkgs.coreutils}/bin/seq 1 ${toString tries}); do
      if ${pkgs.curl}/bin/curl -sf --max-time 5 -o /dev/null ${curlArgs} "${url}"; then
        __wait_ok=1
        break
      fi
      echo "Waiting for ${name}... ($__wait_i/${toString tries})"
      ${pkgs.coreutils}/bin/sleep ${toString interval}
    done
    if [ "$__wait_ok" != 1 ]; then
      echo "${name} did not answer at ${url} within ${toString (tries * interval)}s, giving up" >&2
      exit 1
    fi
    unset __wait_ok __wait_i
  '';
}
