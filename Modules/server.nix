{ self, inputs, ... }: {

  flake.nixosModules.server = { config, pkgs, lib, activeUser, ... }:
  let
    # ── Glance assets (served at /assets/) ──
    glanceAssets = pkgs.runCommand "glance-assets" {} ''
      mkdir -p $out
      cp ${../Resources/yggdrasil-banner.png} $out/yggdrasil.png
    '';

    # ── Glance YAML config (no secrets — reads Prometheus which has no auth) ──
    # Runs as native systemd service (not container) so server-stats widget
    # can read host CPU/memory/disk directly from /proc and /sys.
    glanceConfig = pkgs.writeText "glance.yml" ''
      server:
        port: 8888
        assets-path: ${glanceAssets}

      document:
        head: |
          <style>
            /* ── Global polish ── */
            .widget {
              border: 1px solid hsla(160, 40%, 40%, 0.15);
              border-radius: 12px;
              backdrop-filter: blur(4px);
              transition: border-color 0.3s ease, box-shadow 0.3s ease;
            }
            .widget:hover {
              border-color: hsla(160, 50%, 50%, 0.3);
              box-shadow: 0 0 15px hsla(160, 50%, 40%, 0.08);
            }
            .widget-header .widget-title {
              letter-spacing: 0.08em;
            }

            /* ── Monitor widget tweaks ── */
            .widget-type-monitor .monitor-site {
              border-radius: 8px;
              transition: background-color 0.2s ease;
            }

            /* ── Yggdrasil tree banner ── */
            .ygg-widget {
              position: relative;
            }
            .ygg-widget::before,
            .ygg-widget::after {
              content: "";
              display: block;
              position: absolute;
              top: 0;
              left: 50%;
              transform: translateX(-50%);
              width: 200px;
              height: 200px;
              background-repeat: no-repeat;
              background-position: center;
              background-size: contain;
              pointer-events: none;
            }
            /* Ring — SVG behind the tree */
            .ygg-widget::before {
              background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 400'%3E%3Cdefs%3E%3CradialGradient id='bg' cx='50%25' cy='50%25' r='45%25'%3E%3Cstop offset='0%25' stop-color='hsla(160,30%25,25%25,0.12)'/%3E%3Cstop offset='100%25' stop-color='hsla(160,30%25,15%25,0)'/%3E%3C/radialGradient%3E%3C/defs%3E%3Ccircle cx='200' cy='200' r='180' fill='url(%23bg)'/%3E%3Cg fill='none' stroke='hsla(160,35%25,55%25,0.35)' stroke-width='1.5'%3E%3Ccircle cx='200' cy='200' r='178'/%3E%3Ccircle cx='200' cy='200' r='170'/%3E%3C/g%3E%3Cg fill='hsla(160,40%25,60%25,0.45)' font-family='serif' font-size='14' font-weight='bold'%3E%3Ctext x='200' y='28' text-anchor='middle'%3E%E1%9A%A0 %E1%9A%B1 %E1%9A%A6 %E1%9A%B2 %E1%9A%A8 %E1%9A%B7 %E1%9A%A2%E1%9A%B3 %E1%9A%BE %E1%9A%A9%3C/text%3E%3Ctext transform='translate(375,100) rotate(72)' text-anchor='middle'%3E%E1%9A%B1%E1%9A%A6%E1%9A%B2%E1%9A%A8%E1%9A%B7%3C/text%3E%3Ctext transform='translate(390,240) rotate(90)' text-anchor='middle'%3E%E1%9A%A2%E1%9A%B3%E1%9A%BE%E1%9A%A9%E1%9A%A0%3C/text%3E%3Ctext transform='translate(350,350) rotate(115)' text-anchor='middle'%3E%E1%9A%B1%E1%9A%A6%E1%9A%B7%E1%9A%A8%E1%9A%B2%3C/text%3E%3Ctext x='200' y='390' text-anchor='middle'%3E%E1%9A%BE %E1%9A%A9 %E1%9A%A0 %E1%9A%B1 %E1%9A%A6 %E1%9A%B2 %E1%9A%A8 %E1%9A%B7 %E1%9A%A2%3C/text%3E%3Ctext transform='translate(50,350) rotate(-115)' text-anchor='middle'%3E%E1%9A%B3%E1%9A%BE%E1%9A%A9%E1%9A%A0%E1%9A%B1%3C/text%3E%3Ctext transform='translate(10,240) rotate(-90)' text-anchor='middle'%3E%E1%9A%A6%E1%9A%B2%E1%9A%A8%E1%9A%B7%E1%9A%A2%3C/text%3E%3Ctext transform='translate(25,100) rotate(-72)' text-anchor='middle'%3E%E1%9A%B3%E1%9A%BE%E1%9A%A9%E1%9A%A0%E1%9A%B1%3C/text%3E%3C/g%3E%3Cg fill='none' stroke='hsla(160,35%25,55%25,0.2)' stroke-width='0.6'%3E%3Cpath d='M160,340 Q175,330 190,340 Q195,350 190,360 Q180,365 170,358 Q162,350 160,340Z'/%3E%3Cpath d='M240,340 Q225,330 210,340 Q205,350 210,360 Q220,365 230,358 Q238,350 240,340Z'/%3E%3C/g%3E%3C/svg%3E");
              opacity: 0.8;
              filter: drop-shadow(0 0 12px hsla(160, 50%, 45%, 0.25));
              transition: opacity 0.3s ease, filter 0.3s ease;
            }
            /* Tree image — on top of ring */
            .ygg-widget::after {
              background-image: url("/assets/yggdrasil.png");
              opacity: 0.85;
              filter: drop-shadow(0 0 8px hsla(160, 50%, 40%, 0.3));
              transition: opacity 0.3s ease, filter 0.3s ease;
            }
            .ygg-widget:hover::before,
            .ygg-widget:hover::after {
              opacity: 1;
              filter: drop-shadow(0 0 18px hsla(160, 55%, 50%, 0.4));
            }
            /* Reserve space for the absolutely positioned banner */
            .ygg-widget {
              padding-top: 208px;
            }

            /* ── Subtle divider between widget sections ── */
            /* Direct children only — inside a group widget the tabs are also
               .widget elements, and the descendant selector drew a rule between
               tab panes. */
            .column-full > .widget + .widget {
              border-top: 1px solid hsla(160, 30%, 50%, 0.08);
              padding-top: 4px;
            }

            /* ── Page header ── */
            .page-navigation-item.page-navigation-item-current {
              text-shadow: 0 0 10px hsla(160, 60%, 50%, 0.4);
            }

            /* ── Clock styling ── */
            .widget-type-clock .clock-time {
              text-shadow: 0 0 12px hsla(160, 50%, 50%, 0.25);
            }

            /* ── Network panel (live throughput + speed test) ── */
            .np { display: flex; flex-direction: column; gap: 14px; }
            .np-row { display: flex; gap: 32px; flex-wrap: wrap; }
            .np-cell { flex: 1 1 200px; min-width: 170px; }
            .np-head { display: flex; align-items: baseline; gap: 7px; }
            .np-arrow { font-size: 1.05em; line-height: 1; }
            .np-num {
              font-size: var(--font-size-h2);
              font-weight: 500;
              color: var(--color-text-highlight);
              font-variant-numeric: tabular-nums;
            }
            .np-unit { font-size: var(--font-size-h5); color: var(--color-text-subdue); }
            .np-foot {
              font-size: var(--font-size-h6);
              color: var(--color-text-subdue);
              font-variant-numeric: tabular-nums;
            }
            .np-down { color: var(--color-positive); }
            .np-up { color: hsl(200, 68%, 58%); }

            /* viewBox is stretched to the cell width, so the stroke has to opt
               out of scaling or it goes lumpy on a wide column. */
            .np-spark {
              display: block;
              width: 100%;
              height: 34px;
              margin: 7px 0 5px;
              overflow: visible;
            }
            .np-spark .np-line {
              fill: none;
              stroke: currentColor;
              stroke-width: 1.4;
              stroke-linejoin: round;
              vector-effect: non-scaling-stroke;
            }
            .np-spark .np-fill { fill: currentColor; opacity: 0.13; stroke: none; }

            .np-meta {
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 14px;
              flex-wrap: wrap;
              border-top: 1px solid var(--color-separator);
              padding-top: 11px;
              font-size: var(--font-size-h6);
              color: var(--color-text-subdue);
            }
            .np-btn {
              font: inherit;
              font-size: var(--font-size-h6);
              letter-spacing: 0.06em;
              text-transform: uppercase;
              color: var(--color-text-base);
              background: hsla(160, 40%, 40%, 0.10);
              border: 1px solid hsla(160, 40%, 45%, 0.30);
              border-radius: 7px;
              padding: 5px 13px;
              cursor: pointer;
              transition: background-color 0.2s ease, border-color 0.2s ease;
            }
            .np-btn:hover:not(:disabled) {
              background: hsla(160, 45%, 45%, 0.20);
              border-color: hsla(160, 50%, 50%, 0.50);
            }
            .np-btn:disabled { opacity: 0.5; cursor: default; }
          </style>

          <script>
            // Glance 0.8.5 renders every widget server-side exactly once per page
            // load — page.js calls fetchPageContent() a single time from
            // setupPage() and there is no client-side widget refresh to hook. So
            // the live half of the Network panel is driven from here instead.
            //
            // This has to live in document.head: widget markup is injected with
            // `pageContentElement.innerHTML = ...`, and innerHTML does not execute
            // <script> tags, so the same code inside a custom-api template would
            // never run. Inline handlers would survive, but listeners are attached
            // here to keep Go's template escaping out of the picture entirely.
            //
            // Reads network-panel.py on :9555, which is CORS-open and reachable
            // over the tailnet. Derived from location.hostname on purpose, so this
            // keeps working when the dashboard is opened by IP rather than by name.
            (function () {
              var API = location.protocol + "//" + location.hostname + ":9555";
              var POLL_MS = 2000;
              var started = false;

              function fmt(v) {
                if (typeof v !== "number" || !isFinite(v)) return "--";
                return v >= 100 ? v.toFixed(0) : v.toFixed(1);
              }

              function text(id, value) {
                var el = document.getElementById(id);
                if (el) el.textContent = value;
              }

              // Relative time, recomputed client-side so the "last run" stamp does
              // not go stale on a dashboard that stays open for days.
              function ago(iso) {
                var t = Date.parse(iso);
                if (isNaN(t)) return "never";
                var s = Math.max(0, (Date.now() - t) / 1000);
                if (s < 90) return "just now";
                if (s < 5400) return Math.round(s / 60) + "m ago";
                if (s < 172800) return Math.round(s / 3600) + "h ago";
                return Math.round(s / 86400) + "d ago";
              }

              function spark(id, values) {
                var svg = document.getElementById(id);
                if (!svg || !values || values.length < 2) return;

                var w = 240, h = 34, pad = 2, n = values.length, max = 0;
                for (var i = 0; i < n; i++) if (values[i] > max) max = values[i];
                // Each direction auto-scales to its own peak. A shared scale is
                // more honest but pins the upload trace flat to the floor on an
                // asymmetric line, which reads as "nothing is happening".
                if (max <= 0) max = 1;

                var pts = [];
                for (var j = 0; j < n; j++) {
                  var x = (j / (n - 1)) * w;
                  var y = h - pad - (values[j] / max) * (h - pad * 2);
                  pts.push(x.toFixed(1) + "," + y.toFixed(1));
                }

                var line = "M" + pts.join(" L");
                svg.querySelector(".np-line").setAttribute("d", line);
                svg.querySelector(".np-fill").setAttribute(
                  "d", line + " L" + w + "," + h + " L0," + h + " Z");
              }

              function render(data) {
                var live = data.live || {};
                text("np-down", fmt(live.down));
                text("np-up", fmt(live.up));
                text("np-peak-down", fmt(live.peak_down));
                text("np-peak-up", fmt(live.peak_up));
                spark("np-spark-down", live.hist_down);
                spark("np-spark-up", live.hist_up);

                var st = data.speedtest || {};
                if (st.ok) {
                  text("np-st-down", fmt(st.down));
                  text("np-st-up", fmt(st.up));
                  text("np-st-ping", fmt(st.ping));
                  text("np-st-jitter", fmt(st.jitter));
                  // The separator lives with the value, so "never run" does not
                // render a dangling bullet.
                text("np-st-server", st.server ? "· " + st.server : "");
                  text("np-st-when", ago(st.timestamp));
                }

                var btn = document.getElementById("np-run");
                if (btn) {
                  btn.disabled = !!data.running;
                  btn.textContent = data.running ? "Running" : "Run now";
                }
              }

              function tick() {
                // Nothing to update behind a hidden tab, and the browser throttles
                // these to a crawl anyway.
                if (document.hidden) return;
                fetch(API + "/api", { cache: "no-store" })
                  .then(function (r) { return r.json(); })
                  .then(render)
                  .catch(function () { /* next tick will retry */ });
              }

              function attach() {
                var btn = document.getElementById("np-run");
                if (!btn) return;
                btn.addEventListener("click", function () {
                  btn.disabled = true;
                  btn.textContent = "Running";
                  fetch(API + "/run", { method: "POST" })
                    .then(tick)
                    .catch(function () { btn.textContent = "Failed"; });
                });
              }

              function boot() {
                if (started || !document.getElementById("np-down")) return false;
                started = true;
                attach();
                tick();
                setInterval(tick, POLL_MS);
                document.addEventListener("visibilitychange", function () {
                  if (!document.hidden) tick();
                });
                return true;
              }

              // Widget markup lands asynchronously, well after DOMContentLoaded.
              document.addEventListener("DOMContentLoaded", function () {
                if (boot()) return;
                var obs = new MutationObserver(function () {
                  if (boot()) obs.disconnect();
                });
                obs.observe(document.body, { childList: true, subtree: true });
              });
            })();
          </script>

      theme:
        positive-color: hsl(142, 72%, 39%)
        negative-color: hsl(0, 84%, 60%)

      pages:
        # ════════════════════════════════════════════════════════════════════
        # PAGE 1 — Asgard (host stats, network, service health)
        #
        # There is deliberately NO bookmarks column. Every link it carried was
        # also a monitor row below, and monitor rows are already clickable — the
        # page was listing the same thirteen services twice, which was most of
        # why it scrolled. Add new services to the monitors, not to a sidebar.
        # ════════════════════════════════════════════════════════════════════
        - name: Asgard
          columns:
            - size: full
              widgets:
                - type: server-stats
                  servers:
                    - type: local
                      name: Asgard
                      hide-mountpoints-by-default: true
                      mountpoints:
                        "/data/media":
                          name: Media Pool
                          hide: false

                # No storage widget here — the server-stats widget above already
                # reports the pool as its DISK bar (mountpoint /data/media, named
                # "Media Pool"), so a second readout only duplicated it.
                #
                # Removing it also took out the last browser-side Prometheus poller,
                # and with it a class of silent breakage: that script fetched
                # localhost:9090, which in a browser means the *viewer's* machine, not
                # Asgard — so it had never once updated except when viewed from the
                # server itself. Any browser-side fetch added here must use
                # asgard:<port>; the network panel below does exactly that.

                # ── Network ────────────────────────────────────────────────
                # A group so the live readout and the speed test share one
                # widget slot instead of stacking. Both tabs render from the
                # same /api call on network-panel.py (:9555) — over localhost,
                # because Glance fetches server-side.
                #
                # Glance renders a widget once per page load and never again, so
                # everything below is only the FIRST frame: the poller in
                # document.head takes over by id and keeps it moving. That is
                # also why the ids matter — don't rename one without editing the
                # script. This replaced a `flow` TUI in a read-only ttyd, which
                # spent most of its life showing xterm.js's reconnect banner.
                - type: group
                  widgets:
                    - type: custom-api
                      title: Network
                      cache: 5s
                      url: http://localhost:9555/api
                      template: |
                        <div class="np">
                          <div class="np-row">
                            <div class="np-cell">
                              <div class="np-head">
                                <span class="np-arrow np-down">↓</span>
                                <span class="np-num" id="np-down">{{ printf "%.1f" (.JSON.Float "live.down") }}</span>
                                <span class="np-unit">Mb/s</span>
                              </div>
                              <svg class="np-spark np-down" id="np-spark-down" viewBox="0 0 240 34" preserveAspectRatio="none">
                                <path class="np-fill" d=""></path>
                                <path class="np-line" d=""></path>
                              </svg>
                              <div class="np-foot">
                                download · peak
                                <span id="np-peak-down">{{ printf "%.1f" (.JSON.Float "live.peak_down") }}</span>
                                over {{ .JSON.Int "live.window" }}s
                              </div>
                            </div>
                            <div class="np-cell">
                              <div class="np-head">
                                <span class="np-arrow np-up">↑</span>
                                <span class="np-num" id="np-up">{{ printf "%.1f" (.JSON.Float "live.up") }}</span>
                                <span class="np-unit">Mb/s</span>
                              </div>
                              <svg class="np-spark np-up" id="np-spark-up" viewBox="0 0 240 34" preserveAspectRatio="none">
                                <path class="np-fill" d=""></path>
                                <path class="np-line" d=""></path>
                              </svg>
                              <div class="np-foot">
                                upload · peak
                                <span id="np-peak-up">{{ printf "%.1f" (.JSON.Float "live.peak_up") }}</span>
                                over {{ .JSON.Int "live.window" }}s
                              </div>
                            </div>
                          </div>
                          <div class="np-meta">
                            <span>{{ .JSON.String "live.iface" }} · sampled every second · each trace scaled to its own peak</span>
                          </div>
                        </div>

                    # Upload reads ~30 Mb/s on a 50 Mb/s uplink and that is
                    # correct: wan-egress-shaping puts every WAN-bound packet in
                    # a 30 Mbit htb class. The footnote says so, because this
                    # otherwise looks exactly like a broken uplink.
                    - type: custom-api
                      title: Speed test
                      cache: 30s
                      url: http://localhost:9555/api
                      template: |
                        {{ $ok := .JSON.Bool "speedtest.ok" }}
                        <div class="np">
                          <div class="np-row">
                            <div class="np-cell">
                              <div class="np-head">
                                <span class="np-arrow np-down">↓</span>
                                <span class="np-num" id="np-st-down">{{ if $ok }}{{ printf "%.1f" (.JSON.Float "speedtest.down") }}{{ else }}--{{ end }}</span>
                                <span class="np-unit">Mb/s</span>
                              </div>
                              <div class="np-foot">download</div>
                            </div>
                            <div class="np-cell">
                              <div class="np-head">
                                <span class="np-arrow np-up">↑</span>
                                <span class="np-num" id="np-st-up">{{ if $ok }}{{ printf "%.1f" (.JSON.Float "speedtest.up") }}{{ else }}--{{ end }}</span>
                                <span class="np-unit">Mb/s</span>
                              </div>
                              <div class="np-foot">upload · shaped to 30</div>
                            </div>
                            <div class="np-cell">
                              <div class="np-head">
                                <span class="np-num" id="np-st-ping">{{ if $ok }}{{ printf "%.1f" (.JSON.Float "speedtest.ping") }}{{ else }}--{{ end }}</span>
                                <span class="np-unit">ms</span>
                              </div>
                              <div class="np-foot">
                                ping ·
                                <span id="np-st-jitter">{{ if $ok }}{{ printf "%.1f" (.JSON.Float "speedtest.jitter") }}{{ else }}--{{ end }}</span>
                                ms jitter
                              </div>
                            </div>
                          </div>
                          <div class="np-meta">
                            <span>
                              Ookla, every 6h ·
                              <span id="np-st-when">{{ if $ok }}…{{ else }}never run{{ end }}</span>
                              <span id="np-st-server">{{ if $ok }}· {{ .JSON.String "speedtest.server" }}{{ end }}</span>
                            </span>
                            <button class="np-btn" id="np-run" type="button">Run now</button>
                          </div>
                        </div>

                # ── Service health ─────────────────────────────────────────
                # One group rather than four stacked monitors. "All" is the
                # default tab because that is the question this page exists to
                # answer; the category tabs are for when something is red and
                # you want it isolated. The duplicated checks cost nothing —
                # they are local HTTP GETs on a 1m cache.
                - type: group
                  widgets:
                    - type: monitor
                      title: All
                      cache: 1m
                      sites:
                        - title: Jellyfin
                          url: http://asgard:8096
                          icon: sh:jellyfin
                        - title: Jellyseerr
                          url: http://asgard:5055
                          icon: sh:jellyseerr
                        - title: Immich
                          url: http://asgard:2283
                          icon: sh:immich
                        - title: Audiobookshelf
                          url: http://asgard:13378
                          icon: sh:audiobookshelf
                        - title: SABnzbd
                          url: http://asgard:8080
                          icon: sh:sabnzbd
                        - title: Prowlarr
                          url: http://asgard:9696
                          icon: sh:prowlarr
                        - title: Sonarr
                          url: http://asgard:8989
                          icon: sh:sonarr
                        - title: Radarr
                          url: http://asgard:7878
                          icon: sh:radarr
                        - title: Lidarr
                          url: http://asgard:8686
                          icon: sh:lidarr
                        - title: Shelfarr
                          url: http://asgard:5056
                          icon: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/shelfarr.svg
                        - title: FileBrowser
                          url: http://asgard:8081
                          icon: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/filebrowser.svg
                        - title: Grafana
                          url: http://asgard:3001
                          icon: sh:grafana
                        - title: Prometheus
                          url: http://asgard:9090
                          icon: sh:prometheus
                        - title: Loki
                          url: http://asgard:3100/ready
                          icon: sh:loki

                    - type: monitor
                      title: Media
                      cache: 1m
                      sites:
                        - title: Jellyfin
                          url: http://asgard:8096
                          icon: sh:jellyfin
                        - title: Jellyseerr
                          url: http://asgard:5055
                          icon: sh:jellyseerr
                        - title: Immich
                          url: http://asgard:2283
                          icon: sh:immich
                        - title: Audiobookshelf
                          url: http://asgard:13378
                          icon: sh:audiobookshelf

                    - type: monitor
                      title: Downloads
                      cache: 1m
                      sites:
                        - title: SABnzbd
                          url: http://asgard:8080
                          icon: sh:sabnzbd
                        - title: Prowlarr
                          url: http://asgard:9696
                          icon: sh:prowlarr

                    - type: monitor
                      title: Arr
                      cache: 1m
                      sites:
                        - title: Sonarr
                          url: http://asgard:8989
                          icon: sh:sonarr
                        - title: Radarr
                          url: http://asgard:7878
                          icon: sh:radarr
                        - title: Lidarr
                          url: http://asgard:8686
                          icon: sh:lidarr
                        - title: Shelfarr
                          url: http://asgard:5056
                          icon: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/shelfarr.svg

                    - type: monitor
                      title: Management
                      cache: 1m
                      sites:
                        - title: FileBrowser
                          url: http://asgard:8081
                          icon: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/filebrowser.svg
                        - title: Grafana
                          url: http://asgard:3001
                          icon: sh:grafana
                        - title: Prometheus
                          url: http://asgard:9090
                          icon: sh:prometheus
                        - title: Loki
                          url: http://asgard:3100/ready
                          icon: sh:loki

            - size: small
              widgets:
                - type: clock
                  hour-format: 12h

                - type: custom-api
                  title: Yggdrasil Network
                  css-class: ygg-widget
                  cache: 15s
                  url: http://localhost:9553/status
                  template: |
                    <style>
                      .ts-online {
                        width: 8px;
                        height: 8px;
                        border-radius: 50%;
                        background-color: hsl(142, 72%, 39%);
                        display: inline-block;
                        margin-left: 4px;
                        vertical-align: middle;
                      }
                      .ts-offline {
                        width: 8px;
                        height: 8px;
                        border-radius: 50%;
                        background-color: var(--color-negative);
                        display: inline-block;
                        margin-left: 4px;
                        vertical-align: middle;
                      }
                    </style>
                    <ul class="list list-gap-10 collapsible-container" data-collapse-after="10">
                      <li>
                        <div class="flex items-center gap-10">
                          <div class="grow flex items-center gap-8">
                            <span class="size-h4 block text-truncate color-primary">{{ .JSON.String "self.name" }}</span>
                            <span class="ts-online"></span>
                          </div>
                          <span class="size-h5 color-subtext">{{ .JSON.String "self.ip" }}</span>
                        </div>
                      </li>
                      {{ range .JSON.Array "peers" }}
                      <li>
                        <div class="flex items-center gap-10">
                          <div class="grow flex items-center gap-8">
                            <span class="size-h4 block text-truncate color-primary">{{ .String "name" }}</span>
                            {{ if .Bool "online" }}
                              <span class="ts-online" data-popover-type="text" data-popover-text="Online"></span>
                            {{ else }}
                              <span class="ts-offline" data-popover-type="text" data-popover-text="Offline"></span>
                            {{ end }}
                          </div>
                          <span class="size-h5 color-subtext">{{ .String "ip" }}</span>
                        </div>
                      </li>
                      {{ end }}
                    </ul>

        # ════════════════════════════════════════════════════════════════════
        # PAGE 2 — Downloads (SABnzbd iframe + queue stats)
        # ════════════════════════════════════════════════════════════════════
        - name: Downloads
          columns:
            - size: small
              widgets:
                - type: custom-api
                  title: Queue
                  cache: 15s
                  url: http://asgard:9090/api/v1/query
                  parameters:
                    query: sabnzbd_queue_size
                  template: |
                    <p class="size-h1">{{ .JSON.Int "data.result.0.value.1" }} <span class="size-h4 color-subtext">items</span></p>

                - type: custom-api
                  title: Remaining
                  cache: 15s
                  url: http://asgard:9090/api/v1/query
                  parameters:
                    query: sabnzbd_queue_remaining_bytes / 1073741824
                  template: |
                    <p class="size-h1 color-primary">{{ printf "%.2f" (.JSON.Float "data.result.0.value.1") }} <span class="size-h4 color-subtext">GB</span></p>

                - type: monitor
                  title: Status
                  cache: 1m
                  sites:
                    - title: SABnzbd
                      url: http://asgard:8080
                      icon: sh:sabnzbd
                    - title: Prowlarr
                      url: http://asgard:9696
                      icon: sh:prowlarr

            - size: full
              widgets:
                - type: iframe
                  title: SABnzbd
                  source: http://asgard:8080
                  height: 700

        # ════════════════════════════════════════════════════════════════════
        # PAGE 3 — Terminal (ttyd web console — login as rock, sudo works)
        # ════════════════════════════════════════════════════════════════════
        - name: Terminal
          columns:
            - size: full
              widgets:
                - type: iframe
                  title: Asgard Terminal
                  source: http://asgard:7681
                  height: 700

        # ════════════════════════════════════════════════════════════════════
        # PAGE 4 — Eclipse (TV box: fix-it buttons + live status)
        # Panel served by the eclipse-control service (port 9554), which drives
        # the LibreELEC box over SSH. iframe because Glance's html widget
        # sanitises everything — see Claude/eclipse.md.
        # ════════════════════════════════════════════════════════════════════
        - name: Eclipse
          columns:
            - size: full
              widgets:
                - type: iframe
                  title: Eclipse Control
                  source: http://asgard:9554
                  height: 300
    '';

    # ── Alloy River config (no secrets — ships journald logs to Loki on localhost) ──
    alloyConfig = pkgs.writeText "config.alloy" ''
      // Collect all systemd journal entries
      loki.source.journal "default" {
        forward_to    = [loki.write.local.receiver]
        relabel_rules = loki.relabel.journal_labels.rules
        labels        = { job = "journald" }
      }

      // Extract useful labels from journal fields
      loki.relabel "journal_labels" {
        forward_to = []
        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
        rule {
          source_labels = ["__journal__hostname"]
          target_label  = "host"
        }
        rule {
          source_labels = ["__journal_priority_keyword"]
          target_label  = "level"
        }
      }

      // Write to local Loki instance
      loki.write "local" {
        endpoint {
          url = "http://localhost:3100/loki/api/v1/push"
        }
      }
    '';
  in
  {

    imports = [ inputs.nixflix.nixosModules.default ];

# ══════════════════════════════════════════════════════════════════════════════
# NIXFLIX — Arr Stack + Jellyfin + SABnzbd
# Auto-wires: Prowlarr ↔ Sonarr/Radarr/Lidarr, Seerr ↔ Jellyfin/Sonarr/Radarr
# All API keys pre-generated and stored in sops — fully reproducible on deploy.
#
# Port reference (Tailscale-only unless noted):
#   Sonarr     8989  |  Radarr    7878  |  Lidarr   8686
#   Prowlarr   9696  |  SABnzbd  8080
#   Jellyfin   8096  (+ Cloudflare tunnel at jellyfin.bifrost-vault.com)
#   Jellyseerr 5055  (+ Cloudflare tunnel at requests.bifrost-vault.com)
# ══════════════════════════════════════════════════════════════════════════════

    nixflix = {
      enable = true;
      mediaDir    = "/data/media";
      downloadsDir = "/downloads";
      stateDir    = "/data/.state/services";

      sonarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."sonarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
        };
      };

      radarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."radarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
        };
      };

      lidarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."lidarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
        };
      };

      prowlarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."prowlarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
          indexers = [
            # Usenet (primary)
            {
              name = "Miatrix";
              apiKey._secret = config.sops.secrets."indexer-api-keys/Miatrix".path;
            }
            {
              name = "NZBgeek";
              apiKey._secret = config.sops.secrets."indexer-api-keys/NZBGeek".path;
            }
            {
              name = "NzbPlanet";
              apiKey._secret = config.sops.secrets."indexer-api-keys/NZBPlanet".path;
            }
          ];
        };
      };

      jellyfin = {
        enable = true;
        apiKey._secret = config.sops.secrets."jellyfin-api-key".path;
        users.admin = {
          password._secret = config.sops.secrets."jellyfin-admin-password".path;
          policy.isAdministrator = true;
        };

        network = {
          # Off-site clients reach us through the Cloudflare tunnel, and
          # cloudflared connects to Jellyfin over loopback — so every remote
          # session presented as 127.0.0.1 and Jellyfin classified it as LAN,
          # where bandwidth is assumed unlimited. It therefore never adapted
          # anything: a 35 Mbit 4K HEVC remux was shipped to a TV behind a
          # 30 Mbit shaped uplink, stalling every few seconds.
          #
          # Trusting the proxy's X-Forwarded-For restores the real client IP,
          # which is what makes remoteClientBitrateLimit below fire at all.
          # localNetworkSubnets stays empty (= all RFC1918 is local), so LAN
          # clients are still uncapped and direct-play as before.
          knownProxies = [ "127.0.0.1" ];
        };

        # Bits per second. Sits well inside the 30 Mbit WAN egress cap set by
        # wan-egress-shaping.service, leaving room for two concurrent remote
        # streams. Forces a real *video* transcode: without it Jellyfin only
        # re-encoded audio when a codec was unsupported (IsVideoDirect=true)
        # and passed the full-bitrate 4K video straight through.
        system.remoteClientBitrateLimit = 12000000;

        # Intel QuickSync on i5-14400 (UHD 730) — /dev/dri/renderD128
        encoding = {
          hardwareAccelerationType = "qsv";
          qsvDevice = "/dev/dri/renderD128";
          enableHardwareEncoding = true;
          allowHevcEncoding = true;
          hardwareDecodingCodecs = [ "h264" "hevc" "mpeg2video" "vc1" "vp9" "av1" ];
          enableTonemapping = true;
          enableVppTonemapping = true;

          # Unthrottled, ffmpeg transcodes to the end of the film regardless of
          # playback position and nothing reaps the output — a single 4K title
          # nine minutes in had already left 34 GB / 1399 segments in
          # /var/cache/jellyfin/transcodes. Throttle once the encoder is far
          # enough ahead, and drop segments the client has already fetched.
          enableThrottling = true;
          enableSegmentDeletion = true;
        };
      };

      # Jellyseerr — media request portal (exposed via Cloudflare tunnel)
      seerr = {
        enable = true;
        package = pkgs.jellyseerr;
        apiKey._secret = config.sops.secrets."jellyseerr-api-key".path;
      };

      # SABnzbd usenet download client
      usenetClients.sabnzbd = {
        enable = true;
        settings = {
          misc = {
            api_key._secret  = config.sops.secrets."sabnzbd-api-key".path;
            nzb_key._secret  = config.sops.secrets."sabnzbd-nzb-key".path;
            port = 8080;
            par2_multicore = 1;
            par2_threads = 12;
            abort_max_missing = 10;
            fail_hopeless_jobs = true;
            pause_on_pwrar = 2;            # 0=warn, 1=pause, 2=abort. Abort → Failed status → Decluttarr blocklists + Sonarr/Radarr re-search. Prevents jobs stalling forever on encrypted/corrupt RARs.
            host_whitelist = "asgard,asgard.tailb54b82.ts.net,100.119.193.77,host.containers.internal,10.200.1.2";
            inet_exposure = 4;
            x_frame_options = 0;
            web_color = "Night";
            web_compact = true;
            web_fullscreen = true;
            web_tabbed = true;

            # Performance
            article_cache_size = "1G";     # RAM cache — reduces disk thrashing
            enable_par_cleanup = true;     # delete par2 files after successful repair
            pause_on_post_processing = false; # keep downloading while post-processing

            # Direct Unpack — KEEP OFF. Known SAB bug: starts unrar before deobfuscation
            # completes on obfuscated NZBs → partial extracts → jobs marked failed with full
            # MKV sitting in _FAILED_ folder (forum t=27128). Must set BOTH keys: SAB's
            # test_disk_performance() in directunpacker.py forces direct_unpack=True on any
            # disk >100 MB/s when direct_unpack_tested=False. Setting tested=True skips that.
            direct_unpack = false;
            direct_unpack_tested = true;

            # Cleanup hygiene — SAB doesn't auto-delete partial files by default.
            # delete_failed makes SAB nuke incomplete folder when job transitions to failed
            # (won't catch .1 races or _FAILED_ bug #2840 — the zombie sweeper handles those).
            delete_failed = true;
            history_retention = "30";
            history_retention_option = "days-archive";

            # Skip pre-download article verification. With pre_check=1 SAB scans every
            # article on the server before download starts — adds the "Checking" phase
            # that clogs the queue UI for minutes. Real download already checks article
            # CRCs (verify_xff_header path), pre_check is redundant.
            pre_check = false;

            # SAB upstream default. Was set to 3 from a now-rolled-back perf-tuning attempt.
            max_art_tries = 5;
          };
          servers = [
            {
              name = "FrugalUsenet";
              host = "aunews.frugalusenet.com";
              port = 563;
              username._secret = config.sops.secrets."usenet/frugalusenet/username".path;
              password._secret = config.sops.secrets."usenet/frugalusenet/password".path;
              connections = 60;
              ssl = true;
              priority = 0;
              timeout = 30;
              required = true;
            }
            {
              name = "Newshosting";
              host = "news.newshosting.com";
              port = 563;
              username._secret = config.sops.secrets."usenet/newshosting/username".path;
              password._secret = config.sops.secrets."usenet/newshosting/password".path;
              connections = 30;
              ssl = true;
              priority = 0;
              timeout = 30;
              optional = false;
            }
          ];
        };
      };

    };


    # unrar in SABnzbd service PATH — required for RAR-packed NZBs
    systemd.services.sabnzbd.path = [ pkgs.unrar ];


    # Completes the Jellyseerr setup wizard declaratively:
    # logs in via Jellyfin creds, syncs + enables all libraries, marks initialized.
    # Uses session cookie auth (same as nixflix's seerr-setup) — idempotent.
    systemd.services.seerr-library-setup = {
      description = "Activate all Jellyfin libraries in Jellyseerr";
      after    = [ "seerr.service" "seerr-setup.service" "network.target" ];
      wants    = [ "seerr.service" "seerr-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        SEERR="http://localhost:5055"
        COOKIE="/tmp/seerr-library-setup-cookie"

        # Wait up to 2 minutes for Jellyseerr
        for i in $(seq 1 24); do
          if curl -sf "$SEERR/api/v1/status" > /dev/null 2>&1; then break; fi
          echo "Waiting for Jellyseerr... ($i/24)"
          sleep 5
        done

        # Skip if already initialized
        if curl -s "$SEERR/api/v1/settings/public" | jq -e '.initialized == true' > /dev/null; then
          echo "Jellyseerr already initialized — nothing to do."
          exit 0
        fi

        # Log in with credentials only (no server config — Jellyfin is already wired by nixflix)
        echo "Logging in..."
        ADMIN_PASS=$(cat ${config.sops.secrets."jellyfin-admin-password".path})
        LOGIN_CODE=$(curl -s -c "$COOKIE" -X POST \
          -H "Content-Type: application/json" \
          -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\"}" \
          -w "%{http_code}" -o /dev/null \
          "$SEERR/api/v1/auth/jellyfin")

        if [ "$LOGIN_CODE" != "200" ] && [ "$LOGIN_CODE" != "201" ]; then
          echo "Login failed (HTTP $LOGIN_CODE)" >&2; exit 1
        fi
        echo "Logged in."

        # Sync libraries from Jellyfin and enable all of them
        echo "Syncing libraries..."
        LIBS=$(curl -s -b "$COOKIE" "$SEERR/api/v1/settings/jellyfin/library?sync=true")
        echo "Found: $(echo "$LIBS" | jq -r '.[].name' | tr '\n' ' ')"
        LIBRARY_IDS=$(echo "$LIBS" | jq -r '.[].id' | paste -sd,)

        if [ -n "$LIBRARY_IDS" ]; then
          curl -sf -b "$COOKIE" \
            "$SEERR/api/v1/settings/jellyfin/library?enable=$LIBRARY_IDS" > /dev/null
          echo "Libraries enabled: $LIBRARY_IDS"
        else
          echo "Warning: no libraries found"
        fi

        # Mark setup as complete (dismisses wizard permanently)
        curl -sf -b "$COOKIE" -X POST "$SEERR/api/v1/settings/initialize" > /dev/null

        rm -f "$COOKIE"
        echo "Jellyseerr setup complete."
      '';
    };


# ══════════════════════════════════════════════════════════════════════════════
# BOOKS — Audiobookshelf (server) + Shelfarr (request portal)
# Audiobookshelf: port 13378 — serves ebooks + audiobooks (Jellyfin-style UI)
# Shelfarr:       port 5056  — Jellyseerr-style request portal for books
#   Connects to Prowlarr (search) + SABnzbd (download) → delivers to ABS
#
# Post-boot (one-time): open Shelfarr at localhost:5056 → Admin → Settings:
#   Prowlarr: http://localhost:9696 + prowlarr-api-key (from sops)
#   SABnzbd:  http://localhost:8080 + sabnzbd-api-key (from sops)
#   ABS:      http://localhost:13378 + key from ABS Settings → API Keys
# ══════════════════════════════════════════════════════════════════════════════

    # Audiobookshelf — ebook + audiobook server
    virtualisation.oci-containers.containers.audiobookshelf = {
      image = "ghcr.io/advplyr/audiobookshelf:latest";
      ports = [ "13378:80" ];
      volumes = [
        "/var/lib/audiobookshelf/config:/config"
        "/var/lib/audiobookshelf/metadata:/metadata"
        "/data/media/audiobooks:/audiobooks"
        "/data/media/books:/ebooks"
      ];
      environment = {
        TZ = "Australia/Sydney";
      };
      autoStart = true;
    };

    # Shelfarr — Jellyseerr-style book request portal
    # RAILS_MASTER_KEY is auto-generated on first run and stored in /var/lib/shelfarr.
    # As long as the volume persists, the key is preserved across rebuilds.
    virtualisation.oci-containers.containers.shelfarr = {
      image = "ghcr.io/pedro-revez-silva/shelfarr:latest";
      ports = [ "5056:4000" ];
      volumes = [
        "/var/lib/shelfarr:/rails/storage"
        "/data/media/audiobooks:/audiobooks"
        "/data/media/books:/ebooks"
        "/downloads:/downloads"
      ];
      environment = {
        PUID                = "1000";
        PGID                = "1001";
        SOLID_QUEUE_IN_PUMA = "1";
        HTTP_PORT           = "4000";  # Go proxy port — must differ from Rails/Puma (3000)
      };
      autoStart = true;
    };


    # Homepage removed — replaced by Glance (port 8888)


# ══════════════════════════════════════════════════════════════════════════════
# AUTOMATION — Decluttarr queue cleaner
# Polls arr service APIs to remove stalled/failed downloads automatically.
# DEFERRED until first boot (needs arr API keys generated by services).
# After first boot:
#   1. Retrieve API keys from each service (Settings → General → API Key)
#   2. Add to sops: sops ~/Dots/Secrets/secrets.yaml
#        decluttarr-env: |
#          SONARR_URL=http://localhost:8989
#          SONARR_KEY=<key>
#          RADARR_URL=http://localhost:7878
#          RADARR_KEY=<key>
#          LIDARR_URL=http://localhost:8686
#          LIDARR_KEY=<key>
#          SABNZBD_URL=http://localhost:8080
#          SABNZBD_KEY=<key>
#          REMOVE_STALLED=True
#          REMOVE_FAILED_IMPORTS=True
#          REMOVE_FAILED=True
#          REMOVE_METADATA_MISSING=True
#          REMOVE_ORPHANS=True
#   3. Un-comment container and add `sops.secrets."decluttarr-env" = {};` below
#   4. Rebuild Asgard
# ══════════════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════════════
# QUALITY — Recyclarr (TRaSH Guides quality profile sync)
# Syncs quality profiles + custom formats to Sonarr + Radarr on boot + daily.
#   Sonarr: WEB-1080p + WEB-2160p + Asgard - TV (default, see below)
#   Radarr: Remux-1080p + Remux-2160p + Asgard - Movies (default, see below)
# This fixes grab issues like "only getting Redux" — proper CF scoring applied.
#
# "Asgard - Movies" / "Asgard - TV" (2026-08-16): custom (non-trash_id) merged
# profiles — best compressed quality first (4K, no remux), falling back down
# to whatever's actually available, in one ladder. Remuxes were causing real
# problems (Eclipse's Pi decoder choking on 4K HDR remuxes, WAN bandwidth
# saturation for remote streams — see Claude/eclipse.md) for negligible
# perceptible quality gain. Set as Jellyseerr's default via
# seerr-radarr-profile / seerr-sonarr-profile below, so every user's request
# uses these without having to pick a profile manually.
# ══════════════════════════════════════════════════════════════════════════════

    # ── Missing content search ─────────────────────────────────────────────────
    # Radarr: daily search for all monitored movies without files.
    # Persistent = true → runs immediately on boot if the 4am window was missed.
    systemd.services.radarr-missing-search = {
      description = "Search all missing monitored movies in Radarr";
      after    = [ "radarr.service" ];
      requires = [ "radarr.service" ];
      # Fail closed if the media pool is not mounted — an empty /data/media would make Radarr
      # consider the entire library missing and trigger a mass re-download.
      unitConfig.RequiresMountsFor = [ "/data/media" "/data/.state" ];
      path     = [ pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        curl -sf -X POST \
          -H "X-Api-Key: $RADARR_KEY" \
          -H "Content-Type: application/json" \
          -d '{"name":"MissingMoviesSearch"}' \
          http://localhost:7878/api/v3/command
        echo "Radarr missing movies search triggered."
      '';
    };

    systemd.timers.radarr-missing-search = {
      description = "Radarr missing movies search — on boot + daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnCalendar = "04:00:00";
        Persistent = true;
      };
    };

    # Sonarr: daily search for all monitored episodes without files.
    systemd.services.sonarr-missing-search = {
      description = "Search all missing monitored episodes in Sonarr";
      after    = [ "sonarr.service" ];
      requires = [ "sonarr.service" ];
      # Fail closed if the media pool is not mounted — an empty /data/media would make Sonarr
      # consider the entire library missing and trigger a mass re-download.
      unitConfig.RequiresMountsFor = [ "/data/media" "/data/.state" ];
      path     = [ pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        curl -sf -X POST \
          -H "X-Api-Key: $SONARR_KEY" \
          -H "Content-Type: application/json" \
          -d '{"name":"MissingEpisodeSearch"}' \
          http://localhost:8989/api/v3/command
        echo "Sonarr missing episodes search triggered."
      '';
    };

    systemd.timers.sonarr-missing-search = {
      description = "Sonarr missing episodes search — on boot + daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnCalendar = "04:00:00";
        Persistent = true;
      };
    };

    # Sets Jellyseerr's default Radarr quality profile to "Asgard - Movies"
    # (created by Recyclarr — best-compressed-quality-first, remux excluded).
    # Runs 12min after boot so Recyclarr (5min) has had time to create the
    # profile first. Idempotent — safe to re-run.
    systemd.services.seerr-radarr-profile = {
      description = "Set Jellyseerr default Radarr profile to Asgard - Movies";
      after    = [ "seerr.service" "seerr-setup.service" "radarr.service" "network.target" ];
      wants    = [ "seerr.service" "seerr-setup.service" "radarr.service" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
      };
      # See the Sonarr sibling below: this retried 2665 times before it was
      # caught. Fail after 5 attempts instead.
      unitConfig = {
        StartLimitIntervalSec = 600;
        StartLimitBurst = 5;
      };
      script = ''
        set -euo pipefail
        SEERR="http://localhost:5055"
        RADARR="http://localhost:7878"
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        SEERR_KEY=$(cat ${config.sops.secrets."jellyseerr-api-key".path})

        # Wait up to 2min for Jellyseerr
        for i in $(seq 1 24); do
          if curl -sf "$SEERR/api/v1/status" > /dev/null 2>&1; then break; fi
          echo "Waiting for Jellyseerr... ($i/24)"
          sleep 5
        done

        # Find the "Asgard - Movies" profile ID in Radarr
        PROFILE_ID=$(curl -s -H "X-Api-Key: $RADARR_KEY" "$RADARR/api/v3/qualityprofile" | \
          jq -r '.[] | select(.name == "Asgard - Movies") | .id')

        if [ -z "$PROFILE_ID" ]; then
          echo "Asgard - Movies profile not found in Radarr — Recyclarr may not have run yet." >&2
          exit 1
        fi

        # API key, not a Jellyfin session cookie — the `admin` Jellyfin
        # account is a plain REQUEST-only user in Jellyseerr, so the old
        # cookie flow 403'd on every settings call. See the Sonarr sibling.
        CFG=$(curl -sf -H "X-Api-Key: $SEERR_KEY" "$SEERR/api/v1/settings/radarr")
        INSTANCE_ID=$(echo "$CFG" | jq -r '.[0].id')
        CURRENT_PROFILE=$(echo "$CFG" | jq -r '.[0].activeProfileId')

        if [ "$CURRENT_PROFILE" = "$PROFILE_ID" ]; then
          echo "Jellyseerr already using correct profile — nothing to do."
          exit 0
        fi

        # Update the profile
        UPDATED=$(echo "$CFG" | jq --argjson pid "$PROFILE_ID" \
          '.[0] | .activeProfileId = $pid | .activeProfileName = "Asgard - Movies" | del(.id)')
        curl -sf -X PUT -H "X-Api-Key: $SEERR_KEY" \
          -H "Content-Type: application/json" \
          -d "$UPDATED" \
          "$SEERR/api/v1/settings/radarr/$INSTANCE_ID" > /dev/null

        echo "Jellyseerr Radarr profile updated to Asgard - Movies (ID: $PROFILE_ID)"
      '';
    };

    systemd.timers.seerr-radarr-profile = {
      description = "Set Jellyseerr Radarr profile after Recyclarr runs";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "12min";
        Persistent = true;
      };
    };

    systemd.services.seerr-sonarr-profile = {
      description = "Set Jellyseerr default Sonarr profile to Asgard - TV";
      after    = [ "seerr.service" "seerr-setup.service" "sonarr.service" "network.target" ];
      wants    = [ "seerr.service" "seerr-setup.service" "sonarr.service" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
      };
      # Give up instead of retrying forever. The cookie-auth version below
      # failed every 30s from 2026-07-31 to 2026-08-23 and reached restart
      # counter 2665 — thousands of journal entries, and every
      # `nixos-rebuild switch` exited 4 because of it.
      unitConfig = {
        StartLimitIntervalSec = 600;
        StartLimitBurst = 5;
      };
      script = ''
        set -euo pipefail
        SEERR="http://localhost:5055"
        SONARR="http://localhost:8989"
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        SEERR_KEY=$(cat ${config.sops.secrets."jellyseerr-api-key".path})

        for i in $(seq 1 24); do
          if curl -sf "$SEERR/api/v1/status" > /dev/null 2>&1; then break; fi
          echo "Waiting for Jellyseerr... ($i/24)"
          sleep 5
        done

        # Auth is the API KEY, not a Jellyfin session cookie. The old cookie
        # flow logged in as the Jellyfin `admin` account, which Jellyseerr
        # imported as an ORDINARY user (permissions: 32 = REQUEST only, not
        # ADMIN). Login returned 200, then every /settings/ call returned
        # 403 as a JSON object, and `.[0]` on it produced the long-running
        # "jq: Cannot index object with number" failure. The API key carries
        # full rights and needs no session at all.
        QP=$(curl -s -H "X-Api-Key: $SONARR_KEY" "$SONARR/api/v3/qualityprofile")
        TV_ID=$(echo "$QP"    | jq -r '.[] | select(.name == "Asgard - TV")    | .id')
        ANIME_ID=$(echo "$QP" | jq -r '.[] | select(.name == "Asgard - Anime") | .id')

        if [ -z "$TV_ID" ] || [ -z "$ANIME_ID" ]; then
          echo "Asgard profiles not found in Sonarr — Recyclarr may not have run yet." >&2
          exit 1
        fi

        CFG=$(curl -sf -H "X-Api-Key: $SEERR_KEY" "$SEERR/api/v1/settings/sonarr")
        INSTANCE_ID=$(echo "$CFG" | jq -r '.[0].id')
        CUR_TV=$(echo "$CFG"      | jq -r '.[0].activeProfileId')
        CUR_ANIME=$(echo "$CFG"   | jq -r '.[0].activeAnimeProfileId')

        if [ "$CUR_TV" = "$TV_ID" ] && [ "$CUR_ANIME" = "$ANIME_ID" ]; then
          echo "Jellyseerr already using correct Sonarr profiles — nothing to do."
          exit 0
        fi

        # Anime requests get the anime profile — Jellyseerr keeps a separate
        # activeAnimeProfileId, which the old version pointed at the TV
        # profile too, so anime was never scored with the fansub tiers.
        UPDATED=$(echo "$CFG" | jq --argjson tv "$TV_ID" --argjson an "$ANIME_ID" \
          '.[0] | .activeProfileId = $tv | .activeProfileName = "Asgard - TV"
               | .activeAnimeProfileId = $an | .activeAnimeProfileName = "Asgard - Anime"
               | del(.id)')
        curl -sf -X PUT -H "X-Api-Key: $SEERR_KEY" \
          -H "Content-Type: application/json" \
          -d "$UPDATED" \
          "$SEERR/api/v1/settings/sonarr/$INSTANCE_ID" > /dev/null

        echo "Jellyseerr Sonarr profiles set: TV=$TV_ID anime=$ANIME_ID"
      '';
    };

    systemd.timers.seerr-sonarr-profile = {
      description = "Set Jellyseerr Sonarr profile after Recyclarr runs";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "12min";
        Persistent = true;
      };
    };

    systemd.services.recyclarr-config = {
      description = "Generate Recyclarr config from sops secrets";
      before   = [ "recyclarr-sync.service" ];
      wantedBy = [ "recyclarr-sync.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/recyclarr
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        # TRaSH's config-templates repo deleted includes.json in 2026-07 and renamed everything;
        # `include: - template: …` no longer resolves ANYTHING (there are no include templates any
        # more) and recyclarr hard-errors, so the sync silently did nothing from 2026-07-11 until
        # this was migrated on 2026-08-11.
        #
        # The replacements are whole-config templates, not includes, so their contents are inlined
        # here by trash_id instead. That is deliberate: trash_ids are stable content hashes, whereas
        # template *names* have now churned twice. Scores and CF definitions still come live from
        # the guide on every sync — only the selection is pinned.
        #
        # Equivalent to the old templates: radarr-remux-web-1080p + radarr-remux-web-2160p and
        # sonarr web-1080p + web-2160p, merged into one instance per service (matching how the old
        # include list put both profiles on one instance).
        #
        # Verified 2026-08-11 by diffing every profile before/after: allowed qualities, cutoffs,
        # cutoffFormatScore (10000), minUpgradeFormatScore (1) and upgradeAllowed are all
        # IDENTICAL — the profiles did not get looser. The only change is a month of TRaSH audio
        # scoring (TrueHD ATMOS +5000, DTS X +4500, FLAC/PCM/DD+ …) plus new negatives
        # (Bad Dual Groups, Line/Mic Dubbed, Black and White Editions at -10000). Sonarr's manual
        # "Any 1080p" profile is not managed here and was untouched.
        cat > /var/lib/recyclarr/recyclarr.yml << EOF
sonarr:
  sonarr-main:
    base_url: http://localhost:8989
    api_key: $SONARR_KEY
    quality_definition:
      type: series
    quality_profiles:
      # The stock TRaSH "WEB-1080p" and "WEB-2160p" profiles were REMOVED from
      # this list on 2026-08-23 and deleted from Sonarr by arr-policy.service.
      # They must stay out of here: recyclarr recreates any profile it is
      # told to manage, so leaving the trash_ids would resurrect them on the
      # next sync and put them back in Jellyseerr's dropdown. Everything now
      # sits on the Asgard profiles below.
      # Custom (not trash_id-based) — mirrors "Asgard - Movies": one ladder,
      # best quality first, remux excluded. Deeper fallback than the stock
      # WEB-only profiles above (which allow WEB and nothing else) because
      # older/catalog shows (Voyager, Kitchen Nightmares back-catalog) often
      # only exist as Bluray-1080p, HDTV, or even DVD/SDTV — a WEB-only
      # profile just never grabs them. Upgrading stays on, so anything
      # grabbed low will get replaced automatically if a better release
      # (still non-remux) shows up later.
      - name: Asgard - TV
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: WEB 2160p
        quality_sort: bottom
        qualities:
          - name: WEB 2160p
            qualities:
              - WEBDL-2160p
              - WEBRip-2160p
          - name: Bluray-2160p
          - name: WEB 1080p
            qualities:
              - WEBDL-1080p
              - WEBRip-1080p
          - name: Bluray-1080p
          - name: HDTV-1080p
          - name: WEB 720p
            qualities:
              - WEBDL-720p
              - WEBRip-720p
          - name: Bluray-720p
          - name: HDTV-720p
          - name: DVD
          - name: SDTV
      # Custom (not trash_id-based) — "Asgard - TV" with every 2160p tier
      # removed. For shows whose ONLY 4K source is a Blu-ray remaster rather
      # than a WEB-DL: there the "upgrade to 4K" is a huge size jump for a
      # disc rip, not a like-for-like swap. Measured 2026-08-23 on Game of
      # Thrones — 3.4 GB/ep on disk vs a 17.1 GB/ep median 2160p release
      # (5x), which alone would have added ~1 TB. Everything else that has
      # real 4K WEB-DLs costs only +1.6 to +8.8 GB/ep and stays on Asgard - TV.
      # Assign this per-series; it is not a default for anything.
      - name: Asgard TV - 1080p
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: WEB 1080p
        quality_sort: bottom
        qualities:
          - name: WEB 1080p
            qualities:
              - WEBDL-1080p
              - WEBRip-1080p
          - name: Bluray-1080p
          - name: HDTV-1080p
          - name: WEB 720p
            qualities:
              - WEBDL-720p
              - WEBRip-720p
          - name: Bluray-720p
          - name: HDTV-720p
          - name: DVD
          - name: SDTV
      # Custom (not trash_id-based) — anime needs its own profile because
      # scoring is fundamentally different: release quality is judged by
      # FANSUB/BD GROUP reputation (the Anime Release Groups CFs below), not
      # by resolution/source the way normal TV is. Structure mirrors TRaSH's
      # own "[Anime] Remux-1080p" guide profile (1080p BD as the top tier,
      # HDTV/WEB-1080p merged into a middle tier, 720p as final fallback) —
      # deliberately DROPPING remux from the top tier (TRaSH merges
      # "Bluray-1080p Remux" + "Bluray-1080p" into one tier and lets the
      # Remux Tier custom format bias toward remux; we just don't allow
      # remux at all, same as Asgard - Movies / Asgard - TV). Anime rarely
      # has meaningful 2160p releases, so no 2160p tier here.
      - name: Asgard - Anime
        reset_unmatched_scores:
          enabled: true
        # ENGLISH DUB IS A HARD REQUIREMENT for anime — no dub, no download.
        #
        # Scoring "Anime Dual Audio" highly is NOT enough on its own, which
        # was proved empirically on 2026-08-23: Sonarr ranks QUALITY TIER
        # ahead of custom-format score, so a Japanese Bluray-1080p (score 0)
        # beat a WEB-DL 720p dual-audio release (score 4100) and was grabbed.
        # CF score only breaks ties WITHIN one quality tier.
        #
        # A minimum score is the only lever that rejects non-dubs outright.
        # 2000 is chosen to sit in the gap between the two populations:
        #   best possible non-dub = WEB Tier 01 1700 + boosts 150 + repack 7 = 1857
        #   any dub               = Anime Dual Audio 2000, before any tier
        # Raising the tier scores above ~1990 would close that gap and break
        # this — keep the arithmetic in mind before editing scores below.
        #
        # Consequence, accepted deliberately: an episode with no dub on the
        # indexers stays MISSING rather than grabbing a sub. For a currently
        # airing season the dub can lag the sub by weeks.
        min_format_score: 2000
        upgrade:
          allowed: true
          until_quality: Bluray-1080p
        quality_sort: bottom
        qualities:
          # NO 2160p TIER — deliberate, and re-confirmed 2026-08-23.
          #
          # It was briefly added that day and then removed the same evening.
          # The reasoning for adding it was wrong: JUJUTSU KAISEN S1 looked
          # like it only had English dubs at 2160p, but that was an artefact
          # of the x265 penalty (see the TV-only block above) suppressing the
          # real 1080p dual-audio releases. Once x265 was un-penalised and
          # "Dubs Only" was added, 1080p dubs were plentiful — S01E02 alone
          # had 150 dual-audio releases including Bluray-1080p and WEBDL-1080p.
          #
          # More importantly there is no 4K master to rip. TV anime is
          # mastered at 1080p (often 720p); native 4K anime is essentially
          # nonexistent, and a WEB-DL cannot exceed what the platform
          # streamed. The "2160p B-Global WEB-DL" files were 2.03 GB against
          # 1.54 GB for the native 1080p Crunchyroll rips already on disk —
          # 4x the pixels for 32% more data, i.e. an upscale. TRaSH's own
          # anime profile has no 2160p tier at all and tops out at
          # Bluray-1080p Remux.
          #
          # Do not re-add this because a show "only has dubs at 4K" — check
          # whether a scoring rule is hiding the 1080p ones first.
          - name: Bluray-1080p
          - name: 1080p
            qualities:
              - HDTV-1080p
              - WEBDL-1080p
              - WEBRip-1080p
          - name: 720p
            qualities:
              - HDTV-720p
              - WEBDL-720p
              - WEBRip-720p
    custom_format_groups:
      add:
        - trash_id: 158188097a58d7687dee647e04af0da3  # [Optional] Golden Rule HD
        - trash_id: e3f37512790f00d0e89e54fe5e790d1c  # [Optional] Golden Rule UHD
        - trash_id: 74aff4168620ed49dcc67e92b2c2a5b4  # [Optional] Language Profiles
        - trash_id: f206572b1147d0221bb1c96765b349e8  # [Release Groups] Anime
        - trash_id: 4d3dc16c3ab3adc640afb8d6e3dc2266  # [Optional] Anime Optional (dual audio, uncensored, 10bit)
        - trash_id: 4b196eed652c65ea98d615212040ebe2  # [Required] Anime Versions (v0-v4)
        - trash_id: 85fae4a2294965b75710ef2989c850eb  # [Streaming Services] HD/UHD boost
        - trash_id: 59c3af66780d08332fdc64e68297098f  # [Unwanted] Unwanted Formats
    # Explicit scores for Asgard - TV / Asgard - Anime (custom, non-trash_id
    # profiles). NEEDED — custom_format_groups.add only creates the formats,
    # it does NOT score them for a non-trash_id profile; reset_unmatched_scores
    # then zeroes everything. This is what let 100+ fake "AI Upscale" Star
    # Trek Voyager releases through on 2026-08-17 before it was caught.
    # Every trash_id/score below is the real trash-guide default, fetched
    # directly from TRaSH-Guides/Guides docs/json/sonarr/cf/*.json — not
    # guessed. Re-verify against that repo if these ever look wrong.
    custom_formats:
      - trash_ids:
          - 23297a736ca77c0fc8e70f8edd7ee56c  # Upscaled
          - 9c11cd3f07101cdba90a2d81cf0e56b4  # LQ
          - e2315f990da2e2cbfc9fa5b7a6fcfe48  # LQ (Release Title)
          - 85c61753df5da1fb2aab6f2a47426b09  # BR-DISK
          - 32b367365729d530ca1c124a0b180c64  # Bad Dual Groups
          - fbcb31d8dabd2a319072b84fc0b7249c  # Extras
          # AV1 — on TRaSH's anime unwanted list, and a hard playback
          # constraint here: Eclipse is a Pi 5, which has HEVC hardware
          # decode but NO AV1 decoder, so AV1 falls back to software and
          # struggles. Added 2026-08-23 after raising the dub scores caused
          # Sonarr to grab three [Breeze] "[1080p.AV1][Dual.Audio]" releases
          # — they satisfied "has English audio" and nothing objected.
          - 15a05bc7c1a36e2b57fd628f8977e2fc  # AV1
        score: -10000
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      # TV-ONLY negatives. Both of these are correct for live-action TV and
      # actively harmful for anime, so they are deliberately NOT assigned to
      # Asgard - Anime. TRaSH's anime profile does not use either.
      #
      # "Language: Not Original" rejects releases whose language is not the
      # series' ORIGINAL language. Right for English-origin TV (blocks
      # foreign dubs); backwards for anime, where the original IS Japanese,
      # so an English-dub-only release trips it and takes -10000.
      #
      # "x265 (HD)" targets wasteful x265 re-encodes of live-action HD.
      # Anime is different: 10-bit x265 is the normal, high-quality format
      # for fansub/BD groups, and TRaSH's anime unwanted list is only
      # Anime Raws / Anime LQ Groups / AV1 / Dubs Only / VOSTFR / v0 — no
      # x265 at all. Applying it here scored real 1080p dual-audio releases
      # at -8000 (e.g. [EMBER] Sakamoto Days S01E03 [1080p] [Dual Audio
      # HEVC WEBRip DDP]), which forced a 720p grab on 2026-08-23 because
      # the only unpenalised dub was 720p.
      - trash_ids:
          - ae575f95ab639ba5d15f663bf019e3e8  # Language: Not Original
          - 47435ece6b99a0b477caf360e79ba0bb  # x265 (HD)
        score: -10000
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
      - trash_ids:
          - d0c516558625b04b363fa6c5c2c7cfd4  # WEB Scene
        score: 1600
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - e6258996055b9fbab7e9cb2f75819294  # WEB Tier 01
        score: 1700
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - 58790d4e2fdcd9733aa7ae68ba2bb503  # WEB Tier 02
        score: 1650
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - d84935abd3f8556dcd51d4f27e22d0a6  # WEB Tier 03
        score: 1600
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - 218e93e5702f44a68ad9e3c6ba87d2f0  # HD Streaming Boost
          - 43b3cf48cb385cd3eac608ee6bca7f09  # UHD Streaming Boost
        score: 75
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - ec8fa7296b64e8cd390a1600981f3923  # Repack/Proper
        score: 5
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - eb3d5cc0a2be0db205fb823640db6a3c  # Repack2
        score: 6
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - 44e7c4de10ae50265753082e5dc76047  # Repack3
        score: 7
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      # Anime-only: fansub/BD release-group reputation tiers. This IS the
      # scoring that actually matters for anime — release quality there is
      # judged by which group did the encode, not resolution/source.
      - trash_ids:
          - 949c16fe0a8147f50ba82cc2df9411c9  # Anime BD Tier 01
        score: 1400
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - ed7f1e315e000aef424a58517fa48727  # Anime BD Tier 02
        score: 1300
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 096e406c92baa713da4a72d88030b815  # Anime BD Tier 03
        score: 1200
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 30feba9da3030c5ed1e0f7d610bcadc4  # Anime BD Tier 04
        score: 1100
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 545a76b14ddc349b8b185a6344e28b04  # Anime BD Tier 05
        score: 1000
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 25d2afecab632b1582eaf03b63055f72  # Anime BD Tier 06
        score: 900
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 0329044e3d9137b08502a9f84a7e58db  # Anime BD Tier 07
        score: 800
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - c81bbfb47fed3d5a3ad027d077f889de  # Anime BD Tier 08
        score: 700
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - e0014372773c8f0e1bef8824f00c7dc4  # Anime Web Tier 01
        score: 600
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 19180499de5ef2b84b6ec59aae444696  # Anime Web Tier 02
        score: 500
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - c27f2ae6a4e82373b0f1da094e2489ad  # Anime Web Tier 03
        score: 400
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 4fd5528a3a8024e6b49f9c67053ea5f3  # Anime Web Tier 04
        score: 300
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 29c2a13d091144f63307e4a8ce963a39  # Anime Web Tier 05
        score: 200
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - dc262f88d74c651b12e9d90b39f6c753  # Anime Web Tier 06
        score: 100
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - b4a1b3d705159cdca36d71e57ca86871  # Anime Raws
          - e3515e519f3b1360cbfc17651944354c  # Anime LQ Groups
        score: -10000
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 418f50b10f1907201b6cfdf881f467b7  # Anime Dual Audio (no guide default)
        # DECISIVE, not a nudge. The release-group tiers above top out at
        # 1700, so the old score of 25 was ~50x too small to ever change an
        # outcome — a Japanese-only release from a better fansub group won
        # every time. Audited 2026-08-23: 28 of 162 anime files had no
        # English track at all (JUJUTSU KAISEN S1 was a French Blu-ray rip,
        # SAKAMOTO DAYS had Portuguese and raw-Japanese files). At 2000 a
        # dual-audio release outranks any tier, which is the intended
        # trade — audio language wins over encode quality for this library.
        score: 2000
        assign_scores_to:
          - name: Asgard - Anime
      # "Dubs Only" catches English-dub releases that do NOT advertise dual
      # audio — titles like "Sakamoto Days - 03 [English Dub][1080p]", plus
      # the known dub groups (Yameii, KamiFS, Golumpa, KaiDubs...). The
      # "Anime Dual Audio" CF above cannot match these: its regex looks for
      # a DUAL token or a JA+EN language pair, so a dub-only release scores
      # 0 and is rejected by min_format_score.
      #
      # TRaSH scores this -10000, because their anime guide is written for
      # people who want the ORIGINAL Japanese audio with subs. This library
      # wants the opposite, so the sign is deliberately inverted. Same 2000
      # as dual audio: either one satisfies "has English audio".
      - trash_ids:
          - 9c14d194486c4014d422adc64092d794  # Dubs Only
        score: 2000
        assign_scores_to:
          - name: Asgard - Anime
radarr:
  radarr-main:
    base_url: http://localhost:7878
    api_key: $RADARR_KEY
    quality_definition:
      type: movie
    quality_profiles:
      # "Remux + WEB 1080p" / "Remux + WEB 2160p" were REMOVED here on
      # 2026-08-23 and deleted from Radarr by arr-policy.service — they held
      # zero movies (all 237 are on Asgard - Movies) and only cluttered
      # Jellyseerr. Same rule as the Sonarr block above: if the trash_ids go
      # back in this list, recyclarr recreates the profiles.
      # Custom (not trash_id-based) — no official TRaSH profile spans both
      # resolutions in one ladder. Merges HD Bluray + WEB (d1d67249…) and
      # UHD Bluray + WEB (64fb5f98…) qualities into one profile, remux
      # excluded entirely, so this can never grab/keep a remux release.
      # Upgrading is allowed up to Bluray-2160p, so a 1080p grab will later
      # get replaced by a 4K one if a clean (non-remux) release shows up.
      - name: Asgard - Movies
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: Bluray-2160p
        quality_sort: bottom
        qualities:
          - name: Bluray-2160p
          - name: WEB 2160p
            qualities:
              - WEBRip-2160p
              - WEBDL-2160p
          - name: Bluray-1080p
          - name: WEB 1080p
            qualities:
              - WEBRip-1080p
              - WEBDL-1080p
    custom_format_groups:
      add:
        - trash_id: f8bf8eab4617f12dfdbd16303d8da245  # [Optional] Golden Rule HD
        - trash_id: ff204bbcecdd487d1cefcefdbf0c278d  # [Optional] Golden Rule UHD
        - trash_id: a3ac6af01d78e4f21fcb75f601ac96df  # [Unwanted] Unwanted Formats
    # Explicit scores for Asgard - Movies (custom, non-trash_id profile) —
    # see the matching comment under sonarr-main above for why this is
    # necessary. Real trash-guide defaults, fetched directly from
    # TRaSH-Guides/Guides docs/json/radarr/cf/*.json.
    custom_formats:
      - trash_ids:
          - bfd8eb01832d646a0a89c4deb46f8564  # Upscaled
          - 90a6f9a284dff5103f6346090e6280c8  # LQ
          - e204b80c87be9497a8a6eaff48f72905  # LQ (Release Title)
          - ed38b889b31be83fda192888e2286d83  # BR-DISK
          - b6832f586342ef70d9c128d40c07b872  # Bad Dual Groups
          - dc98083864ea246d05a42df0d05f81cc  # x265 (HD)
          - 0a3f082873eb454bde444150b70253cc  # Extras
          - b8cd450cbfa689c0259a01d9e29ba3d6  # 3D
          - 712d74cd88bceb883ee32f773656b1f5  # Sing-Along Versions
          - cc444569854e9de0b084ab2b8b1532b2  # Black and White Editions
          - c465ccc73923871b3eb1802042331306  # Line/Mic Dubbed
        score: -10000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - c20f169ef63c5f40c2def54abaf4438e  # WEB Tier 01
        score: 1700
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 403816d65392c79236dcb6dd591aeda4  # WEB Tier 02
        score: 1650
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - af94e0fe497124d1f9ce732069ec8c3b  # WEB Tier 03
        score: 1600
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - e7718d7a3ce595f289bfee26adc178f5  # Repack/Proper
        score: 5
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - ae43b294509409a6a13919dedd4764c4  # Repack2
        score: 6
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 5caaaa1c08c1742aa4342d8c4cc463f2  # Repack3
        score: 7
        assign_scores_to:
          - name: Asgard - Movies
      # Audio format hierarchy — real trash-guide defaults
      - trash_ids:
          - 496f355514737f7d83bf7aa4d24f8169  # TrueHD ATMOS
        score: 5000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 2f22d89048b01681dde8afe203bf2e95  # DTS X
        score: 4500
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 1af239278386be2919e1bcee0bde047e  # DD+ ATMOS
        score: 3000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 3cafb66171b47f226146a0770576870f  # TrueHD
        score: 2750
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - dcf3ec6938fa32445f590a4da84256cd  # DTS-HD MA
        score: 2500
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - a570d4a0e56a2874b64e5bfa55202a1b  # FLAC
          - e7c2fcae07cbada050a0af3357491d7b  # PCM
        score: 2250
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 8e109e50e0a0b83a5098b056e13bf6db  # DTS-HD HRA
        score: 2000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 185f1dd7264c4562b9022d963ac37424  # DD+
        score: 1750
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - f9f847ac70a0af62ea4a08280b859636  # DTS-ES
        score: 1500
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 1c1a4c5e823891c75bc50380a6866f73  # DTS
        score: 1250
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 240770601cc226190c367ef59aba7463  # AAC
        score: 1000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - c2998bd0d90ed5621d8df281e839436e  # DD
        score: 750
        assign_scores_to:
          - name: Asgard - Movies
EOF
        chmod 600 /var/lib/recyclarr/recyclarr.yml
      '';
    };

    systemd.services.recyclarr-sync = {
      description = "Sync TRaSH Guides quality profiles via Recyclarr";
      after  = [ "recyclarr-config.service" "sonarr.service" "radarr.service" "network-online.target" ];
      wants  = [ "recyclarr-config.service" "sonarr.service" "radarr.service" "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.recyclarr}/bin/recyclarr sync --config /var/lib/recyclarr/recyclarr.yml";
        # RECYCLARR_APP_DATA was removed upstream — recyclarr now hard-errors on it and the sync
        # never runs. CONFIG_DIR replaces it; DATA_DIR is optional and defaults to CONFIG_DIR.
        Environment = "RECYCLARR_CONFIG_DIR=/var/lib/recyclarr";
      };
    };

    systemd.timers.recyclarr-sync = {
      description = "Daily Recyclarr sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "24h";
      };
    };

    # Per-item state that recyclarr cannot express. Recyclarr owns quality
    # profiles and custom-format SCORES; it has no concept of "which series
    # uses which profile", series type, release profiles, or Jellyfin user
    # settings. Those are per-record database state, so they are applied here
    # over the APIs instead — idempotently, so a fresh install converges to
    # the same place and re-running is a no-op.
    #
    # Ordered after recyclarr-sync: it reads profiles BY NAME and bails out
    # harmlessly if they do not exist yet (first boot, before the first sync).
    systemd.services.arr-policy = {
      description = "Apply per-series / per-user policy to Sonarr, Radarr and Jellyfin";
      # Ordered after the seerr-*-profile units on purpose: Jellyseerr was
      # pointing at the stock "Any" profile (id 1), which this service
      # deletes. Repoint Jellyseerr first, then delete, or requests land on a
      # profile that no longer exists.
      after    = [ "recyclarr-sync.service" "sonarr.service" "radarr.service" "jellyfin.service"
                   "seerr-sonarr-profile.service" "seerr-radarr-profile.service" "network-online.target" ];
      wants    = [ "recyclarr-sync.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -u
        SONARR=http://localhost:8989
        RADARR=http://localhost:7878
        JELLYFIN=http://localhost:8096
        SK=$(cat ${config.sops.secrets."sonarr-api-key".path})
        RK=$(cat ${config.sops.secrets."radarr-api-key".path})
        JK=$(cat ${config.sops.secrets."jellyfin-api-key".path})

        # Wait for Sonarr; everything else is best-effort within this run.
        for i in $(seq 1 30); do
          curl -sf -m 5 -H "X-Api-Key: $SK" $SONARR/api/v3/system/status >/dev/null && break
          sleep 5
        done

        QP=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/qualityprofile) || QP="[]"
        TV=$(echo "$QP"     | jq -r '.[]|select(.name=="Asgard - TV")|.id')
        TV1080=$(echo "$QP" | jq -r '.[]|select(.name=="Asgard TV - 1080p")|.id')
        ANIME=$(echo "$QP"  | jq -r '.[]|select(.name=="Asgard - Anime")|.id')

        if [ -z "$TV" ] || [ -z "$TV1080" ] || [ -z "$ANIME" ]; then
          echo "arr-policy: Asgard profiles not present yet (recyclarr has not synced) - skipping"
          exit 0
        fi

        # --- Sonarr: series -> profile + series type -------------------------
        # Anime gets seriesType=anime so absolute episode numbering parses.
        # Game of Thrones is pinned to the 1080p ladder: its only 4K source is
        # a Blu-ray remaster at ~17 GB/ep vs 3.4 GB/ep on disk (measured
        # 2026-08-23), which would have added ~1 TB on its own.
        SERIES=$(curl -sf -m 30 -H "X-Api-Key: $SK" $SONARR/api/v3/series) || SERIES="[]"
        echo "$SERIES" | jq -c '.[]' | while read -r S; do
          ID=$(echo "$S" | jq -r .id)
          TITLE=$(echo "$S" | jq -r .title)
          case "$TITLE" in
            "SAKAMOTO DAYS"|"Good Night World"|"Sword Art Online"|"Solo Leveling"|"JUJUTSU KAISEN")
              WANT_P=$ANIME;  WANT_T=anime ;;
            "Game of Thrones")
              WANT_P=$TV1080; WANT_T=standard ;;
            *)
              WANT_P=$TV;     WANT_T=standard ;;
          esac
          CUR_P=$(echo "$S" | jq -r .qualityProfileId)
          CUR_T=$(echo "$S" | jq -r .seriesType)
          if [ "$CUR_P" != "$WANT_P" ] || [ "$CUR_T" != "$WANT_T" ]; then
            echo "$S" | jq --argjson p "$WANT_P" --arg t "$WANT_T" \
                  '.qualityProfileId=$p | .seriesType=$t' \
              | curl -sf -m 30 -X PUT -H "X-Api-Key: $SK" \
                     -H 'Content-Type: application/json' --data-binary @- \
                     "$SONARR/api/v3/series/$ID" >/dev/null \
              && echo "arr-policy: $TITLE -> profile $WANT_P / $WANT_T" \
              || echo "arr-policy: FAILED to update $TITLE"
          fi
        done

        # --- Sonarr: block the fake-dual-audio group -------------------------
        # "Anime Dual Audio" matches on the literal token DUAL, so a
        # Portuguese+Japanese release like
        #   SAKAMOTO.DAYS.S01E03.1080p.NF.WEB-DL.DDP5.1.H.264.DUAL-sh4down
        # scores as if it were an English dub. TRaSH's own "Bad Dual Groups"
        # list does NOT include sh4down (checked 2026-08-23, all 34 entries),
        # so it is blocked here. A release profile is used rather than a
        # custom format because recyclarr's reset_unmatched_scores would zero
        # a locally-scored CF on its next sync; it does not touch these.
        # "AV1" is also blocked here, NOT only via the AV1 custom format.
        # TRaSH's AV1 CF regex is \bAV1\b, which does not match a title like
        #   [Breeze].Sakamoto.Days-S01E13.1080p.AV1Dual.Audio.weekly
        # because there is no word boundary between AV1 and Dual. That
        # release scored +2000 on Anime Dual Audio alone and was grabbed on
        # 2026-08-23 despite the CF being at -10000. A release-profile
        # ignored term is a plain substring match, so it has no such gap.
        DESIRED='["sh4down","AV1"]'
        RP=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/releaseprofile) || RP="[]"
        EXISTING=$(echo "$RP" | jq -c '.[]|select(.name=="Asgard - fake dual audio")')
        if [ -z "$EXISTING" ]; then
          curl -sf -m 15 -X POST -H "X-Api-Key: $SK" -H 'Content-Type: application/json' \
            -d "{\"name\":\"Asgard - fake dual audio\",\"enabled\":true,\"required\":[],\"ignored\":$DESIRED,\"indexerId\":0,\"tags\":[]}" \
            $SONARR/api/v3/releaseprofile >/dev/null \
            && echo "arr-policy: created release profile (sh4down, AV1)" \
            || echo "arr-policy: FAILED to create release profile"
        elif [ "$(echo "$EXISTING" | jq -c '.ignored|sort')" != "$(echo "$DESIRED" | jq -c 'sort')" ]; then
          RPID=$(echo "$EXISTING" | jq -r .id)
          echo "$EXISTING" | jq --argjson ig "$DESIRED" '.ignored=$ig' \
            | curl -sf -m 15 -X PUT -H "X-Api-Key: $SK" \
                   -H 'Content-Type: application/json' --data-binary @- \
                   "$SONARR/api/v3/releaseprofile/$RPID" >/dev/null \
            && echo "arr-policy: updated release profile ignored terms" \
            || echo "arr-policy: FAILED to update release profile"
        fi

        # --- Delete the profiles Jellyseerr should not offer -----------------
        # Deliberately an explicit NAME list, not "everything unused": a
        # profile created later on purpose must not be silently destroyed.
        # Sonarr/Radarr refuse to delete a profile still in use, which is the
        # backstop if the reassignment above did not fully land.
        QP=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/qualityprofile) || QP="[]"
        for NAME in "Any" "SD" "HD-720p" "HD-1080p" "Ultra-HD" "HD - 720p/1080p" "Any 1080p" "WEB-1080p" "WEB-2160p"; do
          PID=$(echo "$QP" | jq -r --arg n "$NAME" '.[]|select(.name==$n)|.id')
          if [ -n "$PID" ]; then
            curl -sf -m 15 -X DELETE -H "X-Api-Key: $SK" "$SONARR/api/v3/qualityprofile/$PID" >/dev/null \
              && echo "arr-policy: deleted Sonarr profile $NAME" \
              || echo "arr-policy: kept Sonarr profile $NAME (still in use)"
          fi
        done

        RQP=$(curl -sf -m 15 -H "X-Api-Key: $RK" $RADARR/api/v3/qualityprofile) || RQP="[]"

        # Radarr COLLECTIONS carry their own qualityProfileId, and Radarr
        # counts that as "in use" — so a profile with zero movies still
        # refuses to delete. Found 2026-08-23: 29 collections pinned to
        # "Remux + WEB 1080p" and 19 to "Remux + WEB 2160p", which is why
        # those two survived the first run. Repoint them at Asgard - Movies
        # before the delete loop below.
        MOVIE_P=$(echo "$RQP" | jq -r '.[]|select(.name=="Asgard - Movies")|.id')
        if [ -n "$MOVIE_P" ]; then
          COLS=$(curl -sf -m 30 -H "X-Api-Key: $RK" $RADARR/api/v3/collection) || COLS="[]"
          echo "$COLS" | jq -c '.[]' | while read -r C; do
            CID=$(echo "$C" | jq -r .id)
            CP=$(echo "$C" | jq -r .qualityProfileId)
            if [ "$CP" != "$MOVIE_P" ]; then
              echo "$C" | jq --argjson p "$MOVIE_P" '.qualityProfileId=$p' \
                | curl -sf -m 30 -X PUT -H "X-Api-Key: $RK" \
                       -H 'Content-Type: application/json' --data-binary @- \
                       "$RADARR/api/v3/collection/$CID" >/dev/null \
                && echo "arr-policy: collection $CID -> profile $MOVIE_P" \
                || echo "arr-policy: FAILED to move collection $CID"
            fi
          done
        fi

        for NAME in "Any" "SD" "HD-720p" "HD-1080p" "Ultra-HD" "HD - 720p/1080p" "Remux + WEB 1080p" "Remux + WEB 2160p"; do
          PID=$(echo "$RQP" | jq -r --arg n "$NAME" '.[]|select(.name==$n)|.id')
          if [ -n "$PID" ]; then
            curl -sf -m 15 -X DELETE -H "X-Api-Key: $RK" "$RADARR/api/v3/qualityprofile/$PID" >/dev/null \
              && echo "arr-policy: deleted Radarr profile $NAME" \
              || echo "arr-policy: kept Radarr profile $NAME (still in use)"
          fi
        done

        # --- Jellyfin: make English actually play ----------------------------
        # PlayDefaultAudioTrack=true makes Jellyfin honour the file's default
        # track and IGNORE AudioLanguagePreference entirely. Most anime here
        # ships with Japanese (JUJUTSU KAISEN: French) flagged default, so
        # accounts with a preference set were still getting subs. Rhys is
        # skipped - already configured correctly and left as the control.
        USERS=$(curl -sf -m 15 -H "X-Emby-Token: $JK" $JELLYFIN/Users) || USERS="[]"
        echo "$USERS" | jq -c '.[]' | while read -r U; do
          UNAME=$(echo "$U" | jq -r .Name)
          [ "$UNAME" = "Rhys" ] && continue
          UID_J=$(echo "$U" | jq -r .Id)
          CUR_A=$(echo "$U" | jq -r '.Configuration.AudioLanguagePreference // ""')
          CUR_D=$(echo "$U" | jq -r '.Configuration.PlayDefaultAudioTrack')
          if [ "$CUR_A" != "eng" ] || [ "$CUR_D" != "false" ]; then
            echo "$U" | jq '.Configuration | .AudioLanguagePreference="eng" | .PlayDefaultAudioTrack=false' \
              | curl -sf -m 15 -X POST -H "X-Emby-Token: $JK" \
                     -H 'Content-Type: application/json' --data-binary @- \
                     "$JELLYFIN/Users/$UID_J/Configuration" >/dev/null \
              && echo "arr-policy: Jellyfin user $UNAME -> eng / no default-track override" \
              || echo "arr-policy: FAILED to update Jellyfin user $UNAME"
          fi
        done

        echo "arr-policy: done"
      '';
    };


    systemd.services.decluttarr-config = {
      description = "Generate Decluttarr YAML config from sops secrets";
      wantedBy = [ "podman-decluttarr.service" ];
      before   = [ "podman-decluttarr.service" ];
      partOf   = [ "podman-decluttarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/decluttarr/config
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        LIDARR_KEY=$(cat ${config.sops.secrets."lidarr-api-key".path})
        SABNZBD_KEY=$(cat ${config.sops.secrets."sabnzbd-api-key".path})
        cat > /var/lib/decluttarr/config/config.yaml << EOF
instances:
  sonarr:
    - base_url: http://host.containers.internal:8989
      api_key: $SONARR_KEY
  radarr:
    - base_url: http://host.containers.internal:7878
      api_key: $RADARR_KEY
  lidarr:
    - base_url: http://host.containers.internal:8686
      api_key: $LIDARR_KEY
download_clients:
  sabnzbd:
    - name: SABnzbd
      base_url: http://host.containers.internal:8080
      api_key: $SABNZBD_KEY
jobs:
  remove_stalled: true
  remove_failed_imports: true
  remove_failed_downloads: true
  remove_metadata_missing: true
  remove_orphans: false
EOF
        chmod 600 /var/lib/decluttarr/config/config.yaml
      '';
    };

    virtualisation.oci-containers.containers.decluttarr = {
      image = "ghcr.io/manimatter/decluttarr:latest";
      volumes = [ "/var/lib/decluttarr/config:/app/config" ];
      autoStart = true;
    };


# ══════════════════════════════════════════════════════════════════════════════
# NETWORKING — Tailscale VPN + Cloudflare Tunnel
# Native NixOS services (not containers).
#
# Tailscale: run `sudo tailscale up` after first boot to authenticate.
#
# Cloudflare tunnel setup (one-time before first build):
#   1. dash.cloudflare.com → Zero Trust → Networks → Tunnels → Create tunnel
#   2. Name it "asgard", copy the Tunnel UUID shown on the detail page
#   3. Download/copy the credentials JSON shown during creation
#   4. sops ~/Dots/Secrets/secrets.yaml
#        cloudflare-tunnel: '<full credentials JSON>'
#   5. Replace TUNNEL-UUID-HERE below with the actual UUID
#
# Public URLs (bifrost-vault.com):
#   jellyfin.bifrost-vault.com  → localhost:8096
#   requests.bifrost-vault.com  → localhost:5055
#   photos.bifrost-vault.com    → localhost:2283
# ══════════════════════════════════════════════════════════════════════════════

    # --- Tailscale ---
    services.tailscale = {
      enable = true;
      openFirewall = true;
    };

    # Tailscale status API proxy — exposes node status for Glance dashboard
    # Queries tailscaled Unix socket and serves JSON on localhost:9553
    systemd.services.tailscale-status-proxy = {
      description = "Tailscale status HTTP proxy for Glance";
      after = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.curl pkgs.jq pkgs.python3 ];
      script = ''
        python3 -c '
import http.server, subprocess, json

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            raw = subprocess.check_output([
                "curl", "-sf", "--unix-socket",
                "/var/run/tailscale/tailscaled.sock",
                "http://local-tailscaled.sock/localapi/v0/status"
            ])
            data = json.loads(raw)
            result = {
                "self": {
                    "name": data["Self"]["HostName"],
                    "ip": data["Self"]["TailscaleIPs"][0],
                    "online": data["Self"]["Online"]
                },
                "peers": [
                    {
                        "name": p["HostName"],
                        "ip": p["TailscaleIPs"][0] if p.get("TailscaleIPs") else "",
                        "online": p.get("Online", False)
                    }
                    for p in data.get("Peer", {}).values()
                ]
            }
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(result).encode())
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode())
    def log_message(self, *args):
        pass

http.server.HTTPServer(("127.0.0.1", 9553), Handler).serve_forever()
        '
      '';
      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
      };
    };

    # Eclipse control endpoint — button panel + status JSON, embedded in Glance
    # as an iframe. Drives the LibreELEC TV box (100.80.62.3) over SSH.
    #
    # SSH not Kodi JSON-RPC on purpose: the headline action is "restart Kodi when
    # it has wedged", and a wedged Kodi cannot answer its own API. Kodi's HTTP
    # server is disabled on Eclipse anyway. See Claude/eclipse.md.
    systemd.services.eclipse-control = {
      description = "Eclipse (LibreELEC) control endpoint for Glance";
      after = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.openssh ];
      environment = {
        ECLIPSE_HOST = "100.80.62.3";
        ECLIPSE_KEY = config.sops.secrets."eclipse-ssh-key".path;
        ECLIPSE_PORT = "9554";
        # Glance renders in JetBrains Mono but embeds the font in its Go binary
        # and lives on another port, so the iframe can't borrow it cross-origin.
        # Serve our own copy to keep the panel typographically native.
        ECLIPSE_FONT_DIR = "${pkgs.jetbrains-mono}/share/fonts/WOFF2";
      };
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${../Resources/Eclipse-Control/eclipse-control.py}";
        Restart = "always";
        RestartSec = 5;
      };
    };

    # ── Internet speed test ─────────────────────────────────────────────────────
    # Ookla's official CLI, not speedtest-cli/librespeed — it is the number the
    # ISP will actually argue about, and it needs no server-list curation.
    #
    # Reading the result: DOWNLOAD is the honest line rate. UPLOAD is not — every
    # WAN-bound packet goes through the 30 Mbit htb class in wan-egress-shaping
    # below, so this reports ~30 on a 50 Mbit uplink **by design**. The widget
    # says so next to the figure; don't go hunting for a broken uplink.
    #
    # The download figure is only honest because the run pauses SABnzbd first
    # (see the script). Ookla measures whatever capacity is spare, so before that
    # was added the timer happily fired mid-download and published the leftovers:
    # 47.8 Mb/s against 421 on the same link twenty seconds later.
    systemd.services.speedtest = {
      description = "Internet speed test (Ookla) → /var/lib/speedtest/latest.json";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        # Not optional. The CLI does std::string(getenv("HOME")) unguarded, so
        # with no HOME it aborts on `basic_string::_M_construct null not valid`
        # and dumps core before it ever touches the network. It keeps its
        # license-acceptance flag under $HOME/.config/ookla.
        HOME = "/var/lib/speedtest";
      };
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "speedtest";
        # A test takes ~30s, plus 11s of settling before it; a hung one must not
        # wedge the timer forever.
        TimeoutStartSec = "5m";
        # The queue is resumed here rather than at the end of the script so it
        # happens on *any* stop — including the unit being killed on
        # TimeoutStartSec, which is exactly the case where a script-level trap
        # would be least reliable. The marker is what authorises the resume, so a
        # queue that was already paused by hand is never silently restarted.
        ExecStopPost = pkgs.writeShellScript "speedtest-resume-sab" ''
          [ -e /var/lib/speedtest/.sab-paused ] || exit 0
          ${pkgs.coreutils}/bin/rm -f /var/lib/speedtest/.sab-paused
          key=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets."sabnzbd-api-key".path})
          ${pkgs.curl}/bin/curl -fsS --max-time 10 \
            "http://localhost:8080/api?apikey=$key&output=json&mode=resume" >/dev/null
        '';
      };
      # Written to a temp file and renamed, so a failed or half-written run never
      # replaces a good result — the panel keeps showing the last known-good one.
      script = ''
        out=/var/lib/speedtest/latest.json
        tmp=$(${pkgs.coreutils}/bin/mktemp /var/lib/speedtest/.latest.XXXXXX)
        raw=$(${pkgs.coreutils}/bin/mktemp /var/lib/speedtest/.raw.XXXXXX)

        # Ookla measures spare capacity, not link capacity, so the line has to be
        # quiet or the result is meaningless — SABnzbd alone will happily sit on
        # 245 Mb/s of a 425 Mb/s link and drag the figure down to a fifth of it.
        #
        # set_pause is a pause with a deadline: if this unit dies hard enough
        # that ExecStopPost never runs, SAB resumes by itself after 6 minutes
        # (one past TimeoutStartSec), so a failure here can never strand the
        # queue. Every step fails open — no key, no SAB, no answer, no pause, and
        # the test still runs.
        #
        # The marker is deliberately not cleared here. One left behind means a
        # previous run was killed before ExecStopPost, so letting it survive into
        # this run is what gets the queue resumed at the end of it.
        key=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets."sabnzbd-api-key".path} || true)
        sab="http://localhost:8080/api?apikey=$key&output=json"
        if ${pkgs.curl}/bin/curl -fsS --max-time 10 "$sab&mode=queue" \
             | ${pkgs.gnugrep}/bin/grep -q '"paused":false'; then
          if ${pkgs.curl}/bin/curl -fsS --max-time 10 \
               "$sab&mode=config&name=set_pause&value=6" >/dev/null; then
            ${pkgs.coreutils}/bin/touch /var/lib/speedtest/.sab-paused
          fi
        fi

        # Let the in-flight NNTP connections drain, then log what is *still* on
        # the wire. SAB is the only thing this unit can pause; if a Jellyfin
        # stream or an arr import is running, the figures below are leftovers
        # again and this line is the only way to tell after the fact.
        ${pkgs.coreutils}/bin/sleep 8
        rx1=$(${pkgs.coreutils}/bin/cat /sys/class/net/enp3s0/statistics/rx_bytes)
        ${pkgs.coreutils}/bin/sleep 3
        rx2=$(${pkgs.coreutils}/bin/cat /sys/class/net/enp3s0/statistics/rx_bytes)
        echo "background traffic at test start: $(( (rx2 - rx1) * 8 / 3 / 1000000 )) Mb/s down"

        if ${lib.getExe pkgs.ookla-speedtest} \
             --format=json --accept-license --accept-gdpr > "$raw"; then
          # On the first run of a fresh machine the EULA goes to stdout *ahead*
          # of the JSON, so this takes the result line rather than the whole
          # stream — otherwise latest.json is a licence notice.
          ${pkgs.gnugrep}/bin/grep -m1 '^{' "$raw" > "$tmp" || true
        fi

        if [ -s "$tmp" ]; then
          ${pkgs.coreutils}/bin/mv "$tmp" "$out"
          ${pkgs.coreutils}/bin/rm -f "$raw"
        else
          ${pkgs.coreutils}/bin/rm -f "$tmp" "$raw"
          exit 1
        fi
      '';
    };

    systemd.timers.speedtest = {
      description = "Run an internet speed test every 6 hours";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 00/6:05:00";
        # Catch up after downtime, so the panel is never showing a result from
        # before the last reboot with no explanation.
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };

    # ── Network panel endpoint (port 9555, Tailscale-only) ─────────────────────
    # Backs the Network group on the Glance main page: live throughput sampled
    # from /proc/net/dev plus the last speed-test result, and a POST /run that
    # triggers a fresh test from the "Run now" button.
    #
    # Replaced `flow` inside a second read-only ttyd on :7682. ttyd kills its
    # child whenever the websocket drops — a backgrounded tab was enough — and
    # xterm.js then painted its reconnect banner over the panel, which is what it
    # spent most of its life showing. See Resources/Network-Panel/network-panel.py.
    #
    # Runs as root purely so POST /run can `systemctl start speedtest.service`.
    # It is not exposed beyond the tailnet: 9555 is deliberately absent from
    # allowedTCPPorts and only reachable via trusted tailscale0.
    systemd.services.network-panel = {
      description = "Network throughput + speed test endpoint for Glance";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.systemd ];
      environment = {
        NETPANEL_IFACE = "enp3s0";
        NETPANEL_PORT = "9555";
      };
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${../Resources/Network-Panel/network-panel.py}";
        Restart = "always";
        RestartSec = 5;
      };
    };

    # mergerfs provides mount.fuse.mergerfs, needed to mount the /data/media pool (see below)
    environment.systemPackages = [ pkgs.kitty.terminfo pkgs.mergerfs pkgs.tmux ];

    # Intel QSV / VAAPI runtime for Jellyfin hardware transcoding (UHD 730 / Gen13).
    # Without these, ffmpeg's "vaapi=va:/dev/dri/renderD128,driver=iHD" fails with
    # "unknown libva error" and clients see "fatal playback error".
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-media-driver        # iHD VAAPI driver (required by QSV)
        intel-compute-runtime     # OpenCL — needed for tonemapping filters
        vpl-gpu-rt                # Intel oneVPL runtime (modern QSV)
        libvdpau-va-gl
      ];
    };

    services.cloudflared = {
      enable = true;
      tunnels = {
        "804d54a8-e7ad-4f34-812d-3052cf862c47" = {
          credentialsFile = config.sops.secrets."cloudflare-tunnel".path;
          default = "http_status:404";
          ingress = {
            "jellyfin.bifrost-vault.com"  = "http://localhost:8096";
            "requests.bifrost-vault.com"  = "http://localhost:5055";
            "photos.bifrost-vault.com"    = "http://localhost:2283";
          };
        };
      };
    };

    # ── Mullvad VPN namespace for SABnzbd ──────────────────────────────────────
    # Creates an isolated network namespace with a WireGuard tunnel to Mullvad.
    # SABnzbd runs inside this namespace — all Usenet traffic goes through the VPN.
    # A veth pair bridges the namespace to the host so the SABnzbd web UI (port 8080)
    # remains accessible from Tailscale/LAN.
    #
    # If the VPN goes down, SABnzbd has no network — acts as a kill switch.

    # 1. Create the "vpn" network namespace
    systemd.services."netns-vpn" = {
      description = "VPN network namespace";
      before = [ "network.target" "wg-mullvad.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.iproute2}/bin/ip netns add vpn";
        ExecStop = "${pkgs.iproute2}/bin/ip netns del vpn";
      };
    };

    # 2. WireGuard interface inside the namespace
    systemd.services.wg-mullvad = {
      description = "WireGuard tunnel (Mullvad) in vpn namespace";
      bindsTo = [ "netns-vpn.service" ];
      requires = [ "network-online.target" ];
      after = [ "netns-vpn.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -e
        # Create WireGuard interface and move it into the namespace
        ${pkgs.iproute2}/bin/ip link add wg0 type wireguard
        ${pkgs.iproute2}/bin/ip link set wg0 netns vpn

        # Configure WireGuard with Mullvad credentials
        ${pkgs.iproute2}/bin/ip netns exec vpn \
          ${pkgs.wireguard-tools}/bin/wg set wg0 \
            private-key ${config.sops.secrets."mullvad-wg-private-key".path} \
            peer 4JpfHBvthTFOhCK0f5HAbzLXAVcB97uAkuLx7E8kqW0= \
            allowed-ips 0.0.0.0/0,::/0 \
            endpoint 146.70.200.2:51820 \
            persistent-keepalive 25

        # Assign addresses and bring up
        ${pkgs.iproute2}/bin/ip -n vpn address add 10.66.10.54/32 dev wg0
        ${pkgs.iproute2}/bin/ip -n vpn -6 address add fc00:bbbb:bbbb:bb01::3:a35/128 dev wg0
        ${pkgs.iproute2}/bin/ip -n vpn link set wg0 up
        ${pkgs.iproute2}/bin/ip -n vpn route add default dev wg0
        ${pkgs.iproute2}/bin/ip -n vpn -6 route add default dev wg0

        # Bring up loopback inside namespace
        ${pkgs.iproute2}/bin/ip -n vpn link set lo up
      '';
      preStop = ''
        ${pkgs.iproute2}/bin/ip -n vpn link del wg0 || true
      '';
    };

    # 3. Veth pair — bridges SABnzbd web UI from vpn namespace to host
    #    Host side: veth-vpn-br 10.200.1.1/24
    #    VPN side:  veth-vpn    10.200.1.2/24
    systemd.services.veth-vpn = {
      description = "Veth bridge to vpn namespace (SABnzbd web UI)";
      bindsTo = [ "wg-mullvad.service" ];
      after = [ "wg-mullvad.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -e
        ${pkgs.iproute2}/bin/ip link add veth-vpn-br type veth peer name veth-vpn
        ${pkgs.iproute2}/bin/ip link set veth-vpn netns vpn

        # Host side
        ${pkgs.iproute2}/bin/ip address add 10.200.1.1/24 dev veth-vpn-br
        ${pkgs.iproute2}/bin/ip link set veth-vpn-br up

        # VPN namespace side
        ${pkgs.iproute2}/bin/ip -n vpn address add 10.200.1.2/24 dev veth-vpn
        ${pkgs.iproute2}/bin/ip -n vpn link set veth-vpn up

        # Allow namespace to reach host (for arr API callbacks)
        ${pkgs.iproute2}/bin/ip netns exec vpn \
          ${pkgs.iproute2}/bin/ip route add 10.200.1.1/32 dev veth-vpn
      '';
      preStop = ''
        ${pkgs.iproute2}/bin/ip link del veth-vpn-br || true
      '';
    };

    # 3b. socat proxy — exposes SABnzbd (inside vpn namespace) on host port 8080
    # All access goes through this: web UI, arr callbacks, exporters, Tailscale.
    systemd.services.sabnzbd-proxy = {
      description = "SABnzbd proxy (host:8080 → vpn namespace)";
      bindsTo = [ "veth-vpn.service" ];
      after = [ "veth-vpn.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:8080,fork,reuseaddr,bind=0.0.0.0 TCP:10.200.1.2:8080";
        Restart = "always";
        RestartSec = 2;
      };
    };

    # 4. DNS inside the vpn namespace — Mullvad's DNS server
    environment.etc."netns/vpn/resolv.conf".text = "nameserver 10.64.0.1\n";

    # 4b. WG watchdog — wg-mullvad is a oneshot, so when Mullvad's peer route
    # flaps it doesn't recover on its own (SAB sees "No route to host" until
    # the upstream heals minutes later). This pings the VPN gateway every 60s
    # inside the netns and restarts wg-mullvad on 3 consecutive failures.
    systemd.services.wg-mullvad-watchdog = {
      description = "Restart wg-mullvad when tunnel unreachable";
      after = [ "wg-mullvad.service" ];
      wants = [ "wg-mullvad.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Restart = "always";
        RestartSec = 30;
      };
      script = ''
        FAILS=0
        while true; do
          if ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iputils}/bin/ping -c1 -W3 10.64.0.1 > /dev/null 2>&1; then
            FAILS=0
          else
            FAILS=$((FAILS + 1))
            echo "wg-mullvad ping failed ($FAILS/3)"
            if [ "$FAILS" -ge 3 ]; then
              echo "wg-mullvad unreachable — restarting tunnel"
              ${pkgs.systemd}/bin/systemctl restart wg-mullvad.service
              FAILS=0
              sleep 30
            fi
          fi
          sleep 60
        done
      '';
    };

    # 5. Bind SABnzbd to the vpn namespace
    systemd.services.sabnzbd = {
      bindsTo = [ "wg-mullvad.service" ];
      after = [ "veth-vpn.service" "wg-mullvad.service" ];
      serviceConfig = {
        PrivateNetwork = lib.mkForce false;  # disable nixflix's PrivateNetwork — we use NetworkNamespacePath instead
        NetworkNamespacePath = "/var/run/netns/vpn";
        BindReadOnlyPaths = [ "/etc/netns/vpn/resolv.conf:/etc/resolv.conf" ];
      };
    };



# ══════════════════════════════════════════════════════════════════════════════
# UTILITIES — File Browser
# Port 8081: FileBrowser — full filesystem browser (downloads, media, photos)
#   Credentials managed via sops: admin-username / admin-password
#   filebrowser-credentials.service syncs them on every boot.
# Tailscale-only, not exposed via Cloudflare tunnel.
# ══════════════════════════════════════════════════════════════════════════════

    # Always writes config.yaml on every rebuild — port and sources are
    # infrastructure, not user settings. User prefs live in the database.
    systemd.services.filebrowser-init = {
      description = "Write FileBrowser Quantum config";
      before   = [ "podman-filebrowser.service" ];
      wantedBy = [ "podman-filebrowser.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/filebrowser
        printf 'server:\n  port: 8080\n  sources:\n    - path: /downloads\n      name: downloads\n    - path: /media\n      name: media\n    - path: /photos\n      name: photos\n' \
          > /var/lib/filebrowser/config.yaml
      '';
    };

    virtualisation.oci-containers.containers.filebrowser = {
      image = "ghcr.io/gtsteffaniak/filebrowser:latest";
      ports = [ "8081:8080" ];
      volumes = [
        "/downloads:/downloads"
        "/data/media:/media"
        "/data/photos:/photos"
        "/var/lib/filebrowser:/home/filebrowser/data"
      ];
      user = "root";
      autoStart = true;
    };

    # Syncs admin credentials from sops on every boot.
    # Tries the sops password first (handles already-changed installs),
    # then falls back to "admin" (handles first run with default password).
    systemd.services.filebrowser-credentials = {
      description = "Seed FileBrowser admin credentials from sops";
      after    = [ "podman-filebrowser.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        USERNAME=$(cat ${config.sops.secrets."admin-username".path})
        PASSWORD=$(cat ${config.sops.secrets."admin-password".path})
        BASE="http://localhost:8081"

        # Wait up to 60s for FileBrowser to accept connections
        for i in $(seq 1 30); do
          if curl -s "$BASE" > /dev/null 2>&1; then break; fi
          echo "Waiting for FileBrowser... ($i/30)"
          sleep 2
        done

        # Authenticate — try sops password first, fall back to default "admin"
        # || true on every jq call prevents set -e from exiting on parse errors
        TOKEN=""
        for CURRENT_PASS in "$PASSWORD" "admin"; do
          RESP=$(curl -s -X POST "$BASE/api/login" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"admin\",\"password\":\"$CURRENT_PASS\"}" 2>/dev/null) || true
          TOKEN=$(printf '%s' "$RESP" | jq -r '.token // empty' 2>/dev/null) || true
          [ -n "$TOKEN" ] && break
        done

        if [ -z "$TOKEN" ]; then
          echo "FileBrowser: could not authenticate — skipping credential sync" >&2
          exit 0
        fi

        # Fetch current user object, patch username + password, write back
        USER_DATA=$(curl -s -H "Authorization: Bearer $TOKEN" "$BASE/api/users/1" 2>/dev/null) || true
        UPDATED=$(printf '%s' "$USER_DATA" | jq \
          --arg u "$USERNAME" --arg p "$PASSWORD" \
          '.username = $u | .password = $p' 2>/dev/null) || true

        if [ -z "$UPDATED" ]; then
          echo "FileBrowser: could not build update payload — skipping" >&2
          exit 0
        fi

        curl -s -X PUT "$BASE/api/users/1" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "$UPDATED" > /dev/null

        echo "FileBrowser credentials synced (user: $USERNAME)."
      '';
    };


# ══════════════════════════════════════════════════════════════════════════════
# PHOTOS — Immich photo server
# Native NixOS module — manages its own PostgreSQL and Redis automatically.
# Public URL: photos.bifrost-vault.com (via Cloudflare tunnel)
# Port: 2283
# Post-boot: create admin account at http://localhost:2283 on first visit.
# ══════════════════════════════════════════════════════════════════════════════

    services.immich = {
      enable = true;
      mediaLocation = "/data/photos";
      host = "0.0.0.0";
      openFirewall = false;
    };

    # Immich 2.7+ expects .immich marker files in each subdirectory — create them
    # before the service starts so verifyReadAccess doesn't fail on fresh /data.
    systemd.services.immich-server.serviceConfig.ExecStartPre = lib.mkBefore [
      (pkgs.writeShellScript "immich-init-dirs" ''
        for dir in encoded-video thumbs upload backups library profile; do
          mkdir -p /data/photos/$dir
          touch /data/photos/$dir/.immich
        done
      '')
    ];

    # Seeds the Immich admin account from sops on first boot.
    # /api/auth/admin-signup is only available before any admin exists — idempotent.
    systemd.services.immich-admin-seed = {
      description = "Create Immich admin account from sops";
      after    = [ "immich-server.service" "network.target" ];
      wants    = [ "immich-server.service" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        USERNAME=$(cat ${config.sops.secrets."admin-username".path})
        PASSWORD=$(cat ${config.sops.secrets."admin-password".path})
        BASE="http://localhost:2283"

        # Wait up to 2 minutes for Immich
        for i in $(seq 1 24); do
          if curl -sf "$BASE/api/server/ping" > /dev/null 2>&1; then break; fi
          echo "Waiting for Immich... ($i/24)"
          sleep 5
        done

        CODE=$(curl -s -o /dev/null -w "%{http_code}" \
          -X POST "$BASE/api/auth/admin-signup" \
          -H "Content-Type: application/json" \
          -d "{\"email\":\"$USERNAME@asgard.local\",\"password\":\"$PASSWORD\",\"name\":\"$USERNAME\"}" 2>/dev/null) || true

        if [ "$CODE" = "201" ]; then
          echo "Immich admin created."
        elif [ "$CODE" = "400" ]; then
          echo "Immich admin already exists — skipping."
        else
          echo "Immich admin-signup returned HTTP $CODE" >&2
        fi
      '';
    };


# ══════════════════════════════════════════════════════════════════════════════
# OBSERVABILITY — Prometheus, Exporters, Glance, Loki + Alloy
#
# Architecture: Prometheus is the single collection layer.
#   node_exporter, cAdvisor, Exportarr, SABnzbd exporter → Prometheus (9090)
#   Glance (8888) reads Prometheus via custom-api widgets
#   journald (all units) → Alloy → Loki (3100) → Glance/Grafana
#
# Exporter ports (internal only — Prometheus scrapes, not externally exposed):
#   node_exporter 9100  |  cAdvisor      9101  |  sabnzbd-exporter 9387
#   exportarr-sonarr  9708  |  exportarr-radarr  9709
#   exportarr-lidarr  9710  |  exportarr-prowlarr 9711
# ══════════════════════════════════════════════════════════════════════════════

    # ── Prometheus ─────────────────────────────────────────────────────────────
    services.prometheus = {
      enable = true;
      port = 9090;
      listenAddress = "0.0.0.0";
      retentionTime = "30d";
      extraFlags = [ "--web.cors.origin=.*" ];

      scrapeConfigs = [
        {
          job_name = "node";
          scrape_interval = "5s";
          static_configs = [{ targets = [ "localhost:9100" ]; }];
        }
        {
          job_name = "cadvisor";
          scrape_interval = "15s";
          static_configs = [{ targets = [ "localhost:9101" ]; }];
        }
        {
          job_name = "exportarr-sonarr";
          static_configs = [{ targets = [ "localhost:9708" ]; }];
        }
        {
          job_name = "exportarr-radarr";
          static_configs = [{ targets = [ "localhost:9709" ]; }];
        }
        {
          job_name = "exportarr-lidarr";
          static_configs = [{ targets = [ "localhost:9710" ]; }];
        }
        {
          job_name = "exportarr-prowlarr";
          static_configs = [{ targets = [ "localhost:9711" ]; }];
        }
        {
          job_name = "sabnzbd";
          static_configs = [{ targets = [ "localhost:9387" ]; }];
        }
      ];
    };

    # ── node_exporter — host system metrics ────────────────────────────────────
    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
      enabledCollectors = [ "systemd" "processes" ];
    };

    # ── cAdvisor — per-container CPU / mem / net metrics ───────────────────────
    # Runs as an oci-container; mounts Podman socket for container discovery.
    # --privileged + /sys mount required for kernel-level cgroup stats.
    virtualisation.oci-containers.containers.cadvisor = {
      image = "gcr.io/cadvisor/cadvisor:latest";
      ports = [ "9101:8080" ];
      volumes = [
        "/:/rootfs:ro"
        "/var/run:/var/run:ro"
        "/sys:/sys:ro"
        "/run/podman/podman.sock:/run/podman/podman.sock:ro"
      ];
      extraOptions = [
        "--privileged"
        "--device=/dev/kmsg"
      ];
      cmd = [
        "--docker=unix:///run/podman/podman.sock"
        "--docker_only=true"
        "--store_container_labels=false"
      ];
      autoStart = true;
    };

    # ── Exportarr — per-service metrics for the arr stack ──────────────────────
    services.prometheus.exporters.exportarr-sonarr = {
      enable = true;
      port = 9708;
      url = "http://localhost:8989";
      apiKeyFile = config.sops.secrets."sonarr-api-key".path;
    };

    services.prometheus.exporters.exportarr-radarr = {
      enable = true;
      port = 9709;
      url = "http://localhost:7878";
      apiKeyFile = config.sops.secrets."radarr-api-key".path;
    };

    services.prometheus.exporters.exportarr-lidarr = {
      enable = true;
      port = 9710;
      url = "http://localhost:8686";
      apiKeyFile = config.sops.secrets."lidarr-api-key".path;
    };

    services.prometheus.exporters.exportarr-prowlarr = {
      enable = true;
      port = 9711;
      url = "http://localhost:9696";
      apiKeyFile = config.sops.secrets."prowlarr-api-key".path;
    };

    # ── SABnzbd exporter ────────────────────────────────────────────────────────
    # Writes env file from sops before container starts (same pattern as Decluttarr).
    systemd.services.sabnzbd-exporter-env = {
      description = "Generate SABnzbd exporter env file from sops";
      wantedBy  = [ "podman-sabnzbd-exporter.service" ];
      before    = [ "podman-sabnzbd-exporter.service" ];
      partOf    = [ "podman-sabnzbd-exporter.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/sabnzbd-exporter
        {
          printf 'SABNZBD_BASEURLS=http://host.containers.internal:8080\n'
          printf 'SABNZBD_APIKEYS=%s\n' \
            "$(cat ${config.sops.secrets."sabnzbd-api-key".path})"
        } > /var/lib/sabnzbd-exporter/env
        chmod 600 /var/lib/sabnzbd-exporter/env
      '';
    };

    virtualisation.oci-containers.containers.sabnzbd-exporter = {
      image = "docker.io/msroest/sabnzbd_exporter:latest";
      ports = [ "9387:9387" ];
      environmentFiles = [ "/var/lib/sabnzbd-exporter/env" ];
      autoStart = true;
    };

    # ── Glance — observability dashboard (port 8888) ────────────────────────────
    # ── Glance — native systemd service for host-level server-stats ──
    systemd.services.glance = {
      description = "Glance Dashboard";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.glance}/bin/glance --config ${glanceConfig}";
        Restart = "on-failure";
        DynamicUser = true;
      };
    };

    # ── ttyd — web terminal (port 7681, Tailscale-only) ─────────────────────────
    # Embedded as the "Terminal" page in Glance. Default entrypoint is `login`
    # (runs as root), so the browser gets a real login prompt — no unauthenticated
    # shell exposed to the tailnet.
    services.ttyd = {
      enable = true;
      port = 7681;
      writeable = true;
    };

    # ttyd sessions die when the browser tab loses focus or closes — the websocket
    # drops and ttyd kills the shell. Detect a ttyd-spawned shell by walking up the
    # process tree, then exec into a persistent tmux session: disconnecting then only
    # kills the tmux client, not the session, so reconnecting reattaches exactly where
    # it left off.
    #
    # This lives HERE, in the Asgard-only server module, and deliberately NOT in the
    # shared Modules/zsh.nix — that one is imported by every host and this behaviour is
    # only wanted on the server. `programs.zsh.initContent` is a `lines` option, so this
    # concatenates with the shared definition rather than replacing it.
    # tmux itself is installed via environment.systemPackages in this same module.
    home-manager.users.${activeUser}.programs.zsh.initContent = lib.mkAfter ''
      if [[ $- == *i* ]] && [[ -z "$TMUX" ]]; then
        __pid=$$
        for __i in 1 2 3 4 5 6; do
          __ppid=$(ps -o ppid= -p "$__pid" 2>/dev/null | tr -d ' ')
          [[ -z "$__ppid" || "$__ppid" -eq 1 ]] && break
          if [[ "$(ps -o comm= -p "$__ppid" 2>/dev/null)" == "ttyd" ]]; then
            exec tmux new-session -A -s ttyd
          fi
          __pid=$__ppid
        done
        unset __pid __ppid __i
      fi
    '';

    # ── Loki — log storage ──────────────────────────────────────────────────────
    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server.http_listen_port = 3100;

        ingester = {
          lifecycler = {
            address = "127.0.0.1";
            ring = {
              kvstore.store = "inmemory";
              replication_factor = 1;
            };
            final_sleep = "0s";
          };
          chunk_idle_period    = "1h";
          max_chunk_age        = "1h";
          chunk_target_size    = 1048576;
          chunk_retain_period  = "30s";
        };

        schema_config.configs = [{
          from         = "2024-01-01";
          store        = "tsdb";
          object_store = "filesystem";
          schema       = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }];

        storage_config = {
          tsdb_shipper = {
            active_index_directory = "/var/lib/loki/tsdb-index";
            cache_location         = "/var/lib/loki/tsdb-cache";
          };
          filesystem.directory = "/var/lib/loki/chunks";
        };

        limits_config = {
          reject_old_samples         = true;
          reject_old_samples_max_age = "168h";
        };

        compactor.working_directory = "/var/lib/loki/compactor";
      };
    };

    # ── Grafana — metrics and log viewer (port 3001) ───────────────────────────
    # Loki (logs) + Prometheus (metrics) auto-provisioned as datasources.
    # To explore logs: Explore → Loki → filter {unit="sonarr.service"} etc.
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_port = 3001;
          http_addr = "0.0.0.0";
        };
        security = {
          admin_user  = "admin";
          admin_password = "$__file{${config.sops.secrets."grafana-admin-password".path}}";
          allow_embedding = true;
          # 26.05 removed the default secret_key; pin the historical default so
          # existing DB-encrypted values (if any) remain decryptable.
          secret_key = "SW2YcwTIb9zpOOhoPsMm";
        };
        "auth.anonymous" = {
          enabled  = true;
          org_role = "Viewer";
        };
        analytics.reporting_enabled = false;
        users.allow_sign_up = false;
      };

      provision.datasources.settings = {
        apiVersion = 1;
        datasources = [
          {
            name      = "Loki";
            type      = "loki";
            url       = "http://localhost:3100";
            access    = "proxy";
            isDefault = true;
            jsonData.maxLines = 5000;
          }
          {
            name   = "Prometheus";
            type   = "prometheus";
            url    = "http://localhost:9090";
            access = "proxy";
          }
        ];
      };

      provision.dashboards.settings.providers = [{
        name = "system";
        options.path = pkgs.writeTextDir "system-stats.json" (builtins.toJSON {
          uid = "asgard-system";
          title = "System Stats";
          timezone = "browser";
          refresh = "1s";
          time = { from = "now-1h"; to = "now"; };
          schemaVersion = 42;
          panels = [
            # ── CPU % (time series, dark green) ──
            {
              id = 1; type = "timeseries"; title = "CPU";
              gridPos = { h = 4; w = 12; x = 0; y = 0; };
              datasource = "Prometheus";
              targets = [{
                refId = "A";
                datasource = "Prometheus";
                expr = ''100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m]))) * 100'';
                legendFormat = "CPU %";
              }];
              fieldConfig.defaults = {
                unit = "percent"; min = 0; max = 100;
                color.mode = "fixed";
                color.fixedColor = "dark-green";
                custom = {
                  fillOpacity = 20;
                  lineWidth = 2;
                  pointSize = 1;
                  showPoints = "never";
                  spanNulls = true;
                };
              };
              options = {
                legend.displayMode = "hidden";
                tooltip.mode = "single";
              };
            }
            # ── Memory (bar gauge: used / total GiB) ──
            {
              id = 2; type = "bargauge"; title = "Memory";
              gridPos = { h = 4; w = 12; x = 12; y = 0; };
              datasource = "Prometheus";
              targets = [
                {
                  refId = "A"; datasource = "Prometheus";
                  expr = "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)";
                  legendFormat = "Used";
                }
                {
                  refId = "B"; datasource = "Prometheus";
                  expr = "node_memory_MemTotal_bytes";
                  legendFormat = "Total";
                }
              ];
              fieldConfig.defaults = {
                unit = "bytes";
                color.mode = "fixed";
                color.fixedColor = "dark-yellow";
                thresholds = {
                  mode = "absolute";
                  steps = [{ color = "dark-yellow"; value = null; }];
                };
              };
              options = {
                reduceOptions = { calcs = [ "lastNotNull" ]; fields = ""; values = false; };
                displayMode = "gradient";
                orientation = "horizontal";
                valueMode = "color";
                namePlacement = "auto";
                showUnfilled = true;
              };
            }
            # ── Media pool /data/media (bar gauge: used / free / total) ──
            # Queries /data/media, not /data — /data stopped being a mountpoint when the two HDDs
            # were pooled by mergerfs. node_exporter reports the pool (~19.8 TB) at /data/media.
            {
              id = 4; type = "bargauge"; title = "Media Pool";
              gridPos = { h = 4; w = 12; x = 12; y = 4; };
              datasource = "Prometheus";
              targets = [
                {
                  refId = "A"; datasource = "Prometheus";
                  expr = ''node_filesystem_size_bytes{mountpoint="/data/media"} - node_filesystem_avail_bytes{mountpoint="/data/media"}'';
                  legendFormat = "Used";
                }
                {
                  refId = "B"; datasource = "Prometheus";
                  expr = ''node_filesystem_avail_bytes{mountpoint="/data/media"}'';
                  legendFormat = "Free";
                }
                {
                  refId = "C"; datasource = "Prometheus";
                  expr = ''node_filesystem_size_bytes{mountpoint="/data/media"}'';
                  legendFormat = "Total";
                }
              ];
              fieldConfig.defaults = {
                unit = "bytes";
                color.mode = "fixed";
                color.fixedColor = "dark-red";
                thresholds = {
                  mode = "absolute";
                  steps = [{ color = "dark-red"; value = null; }];
                };
              };
              options = {
                reduceOptions = { calcs = [ "lastNotNull" ]; fields = ""; values = false; };
                displayMode = "gradient";
                orientation = "horizontal";
                valueMode = "color";
                namePlacement = "auto";
                showUnfilled = true;
              };
            }
            # ── Network (time series, purple) ──
            {
              id = 3; type = "timeseries"; title = "Network";
              gridPos = { h = 4; w = 12; x = 0; y = 4; };
              datasource = "Prometheus";
              targets = [
                {
                  refId = "A"; datasource = "Prometheus";
                  expr = ''rate(node_network_receive_bytes_total{device="enp10s0"}[2m]) * 8 / 1000000'';
                  legendFormat = "Download";
                }
                {
                  refId = "B"; datasource = "Prometheus";
                  expr = ''rate(node_network_transmit_bytes_total{device="enp10s0"}[2m]) * 8 / 1000000'';
                  legendFormat = "Upload";
                }
              ];
              fieldConfig.defaults = {
                unit = "Mbps"; min = 0;
                custom = {
                  fillOpacity = 15;
                  lineWidth = 2;
                  pointSize = 1;
                  showPoints = "never";
                  spanNulls = true;
                };
              };
              fieldConfig.overrides = [
                { matcher = { id = "byName"; options = "Download"; }; properties = [{ id = "color"; value = { mode = "fixed"; fixedColor = "dark-purple"; }; }]; }
                { matcher = { id = "byName"; options = "Upload"; }; properties = [{ id = "color"; value = { mode = "fixed"; fixedColor = "light-purple"; }; }]; }
              ];
              options = {
                legend.displayMode = "list";
                legend.placement = "bottom";
                tooltip.mode = "multi";
              };
            }
          ];
        });
      }];
    };

    # ── Alloy — journald → Loki pipeline ───────────────────────────────────────
    # Single journald scrape captures ALL units: native NixOS services (immich,
    # sonarr, radarr, etc.) AND podman containers (podman-kavita.service, etc.).
    # Config is static (no secrets) so it lives in the Nix store.
    services.alloy = {
      enable = true;
      configPath = alloyConfig;
    };
    # Alloy needs read access to the systemd journal
    systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "systemd-journal" ];


# ══════════════════════════════════════════════════════════════════════════════
# INFRASTRUCTURE — Podman, media group, data directories, sops secrets
# ══════════════════════════════════════════════════════════════════════════════

    # --- Podman (OCI backend for containers: Kavita, FileBrowser, cAdvisor, exporters, Glance) ---
    virtualisation.oci-containers.backend = "podman";
    virtualisation.podman = {
      enable = true;
      dockerSocket.enable = true; # activates podman.socket at /run/podman/podman.sock (used by cAdvisor)
    };
    # Allow containers to reach host-bound services (arr, immich, etc.)
    # tailscale0 trusted so all services are reachable from any tailnet device by hostname
    networking.firewall.trustedInterfaces = [ "podman0" "cni-podman0" "tailscale0" ];
    networking.firewall.allowedTCPPorts = [
      8096 # Jellyfin — open to LAN so home devices connect directly (no CF tunnel / upload round-trip)
    ]; # everything else accessed via Tailscale (trustedInterfaces)

    # --- WAN egress shaping ---
    # Jellyfin's transcoder delivers segments in on/off bursts that momentarily
    # saturate the full 50 Mbit uplink (~180ms latency spikes every ~3s, which
    # rubber-bands game sessions on the LAN). Cap WAN-bound traffic at 30 Mbit
    # so it flows smoothly below line rate; LAN/tailnet destinations (RFC1918)
    # bypass the cap so local direct-play of high-bitrate remuxes is unaffected.
    systemd.services.wan-egress-shaping = {
      description = "Cap WAN-bound upload at 30 Mbit (smooth Jellyfin transcode bursts)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        tc=${pkgs.iproute2}/bin/tc
        dev=enp3s0
        # htb doesn't support in-place change, so "replace" fails on an existing
        # root — tear down and rebuild from scratch (also clears classes/filters)
        $tc qdisc del dev $dev root 2>/dev/null || true
        $tc qdisc add dev $dev root handle 1: htb default 20
        $tc class add dev $dev parent 1: classid 1:1 htb rate 940mbit
        $tc class add dev $dev parent 1:1 classid 1:10 htb rate 910mbit ceil 940mbit
        $tc class add dev $dev parent 1:1 classid 1:20 htb rate 30mbit ceil 30mbit
        $tc qdisc add dev $dev parent 1:20 fq_codel
        $tc filter add dev $dev parent 1: protocol ip prio 1 u32 match ip dst 192.168.0.0/16 flowid 1:10
        $tc filter add dev $dev parent 1: protocol ip prio 1 u32 match ip dst 10.0.0.0/8 flowid 1:10
        $tc filter add dev $dev parent 1: protocol ip prio 1 u32 match ip dst 172.16.0.0/12 flowid 1:10
      '';
    };

    # DNS inside the VPN namespace (SABnzbd's sandbox) fails due to routing
    # conflicts. Bypass it entirely for the usenet server — /etc/hosts is read
    # first (nsswitch: files before dns), so getaddrinfo() never touches DNS.
    # IPs confirmed reachable via the Mullvad tunnel on port 563.
    networking.hosts = {
      "45.125.247.68"  = [ "aunews.frugalusenet.com" ];
      "45.125.247.108" = [ "aunews.frugalusenet.com" ];
      "85.12.62.251"   = [ "news.newshosting.com" ];
    };

    # IP forwarding — required for veth NAT (SABnzbd web UI from vpn namespace)
    boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkDefault true;

    # --- Claude Code auth ---
    # OAuth credentials live in ~/.claude/.credentials.json (set up via `claude login`).
    # managed-settings intentionally left empty so OAuth takes precedence.

    # --- Shared media group (GID 1001) ---
    # All service users and containers use this group for /data/media access.
    users.groups.media = { gid = 1001; };
    users.users.${activeUser}.extraGroups = [ "media" ];
    users.users.jellyfin.extraGroups = [ "media" "render" "video" ];

    # ══════════════════════════════════════════════════════════════════════════
    # Storage pool — mergerfs unites the 8TB + 12TB into one /data/media
    # ══════════════════════════════════════════════════════════════════════════
    #
    #   /mnt/disk1   8TB  ext4   ─┐
    #                             ├─ mergerfs ──> /data/media
    #   /mnt/disk2   12TB ext4   ─┘
    #
    #   /data/photos  <- bind /mnt/disk1/photos   (Immich)
    #   /data/.state  <- bind /mnt/disk1/.state   (arr SQLite DBs)
    #
    # mergerfs is a UNION filesystem: it merges the directory tree, not blocks. Every file lives
    # whole on exactly one disk, and the pool is a single namespace so each file appears exactly
    # once. Losing a drive costs only that drive's files — the survivor keeps serving. This is
    # why mergerfs and NOT LVM/btrfs-single/RAID0, which span one filesystem across both spindles
    # and lose everything if either disk dies.
    #
    # Only MEDIA is pooled. The arr databases (/data/.state) and Immich's library (/data/photos)
    # stay on real ext4 via bind mounts — SQLite on FUSE is a known source of locking corruption,
    # and those two are only ~3.8G combined, so there is no capacity reason to pool them.
    #
    # Every service path is unchanged by this: nixflix mediaDir/stateDir, the container bind
    # mounts, immich mediaLocation and the tmpfiles rules below all still point at /data/...
    #
    # NOTE: /mnt/disk2/media must exist before the pool can mount — mergerfs errors on a missing
    # branch, and tmpfiles runs too late to help. It was created by hand at install time.
    # (pkgs.mergerfs is added to environment.systemPackages above, next to kitty.terminfo)
    programs.fuse.userAllowOther = true;  # required for allow_other

    fileSystems."/data/media" = {
      device = "/mnt/disk1/media:/mnt/disk2/media";
      fsType = "fuse.mergerfs";
      options = [
        "category.create=mfs"   # new files -> branch with most free space (the 12TB)
        "moveonenospc=true"     # branch fills mid-write -> relocate rather than ENOSPC
        "minfreespace=50G"      # stop choosing a branch below this
        "cache.files=partial"
        "dropcacheonclose=true"
        "allow_other"           # podman containers + non-root services must read it
        "fsname=mediapool"
        "nofail"
        "x-systemd.requires-mounts-for=/mnt/disk1"
        "x-systemd.requires-mounts-for=/mnt/disk2"
      ];
    };

    fileSystems."/data/photos" = {
      device = "/mnt/disk1/photos";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.requires-mounts-for=/mnt/disk1" ];
    };

    fileSystems."/data/.state" = {
      device = "/mnt/disk1/.state";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.requires-mounts-for=/mnt/disk1" ];
    };

    # Hard mount dependencies — SAFETY CRITICAL.
    # If the pool fails to mount, /data/media is an empty directory on the NVMe. Services must
    # refuse to start rather than run against an empty library: Jellyfin would blank the library,
    # and the *-missing-search units would trigger a mass re-download of the entire collection.
    # RequiresMountsFor makes each unit fail closed instead.
    # NOTE: these must be written as dotted paths, not `systemd.services = lib.genAttrs ...`.
    # Nix merges dotted paths into attrset *literals* only — a computed expression collides with
    # the many `systemd.services.<name> = { ... }` definitions elsewhere in this file.
    systemd.services.sonarr.unitConfig.RequiresMountsFor              = [ "/data/media" "/data/.state" ];
    systemd.services.radarr.unitConfig.RequiresMountsFor              = [ "/data/media" "/data/.state" ];
    systemd.services.lidarr.unitConfig.RequiresMountsFor              = [ "/data/media" "/data/.state" ];
    systemd.services.jellyfin.unitConfig.RequiresMountsFor            = [ "/data/media" "/data/.state" ];
    systemd.services.sonarr-rootfolders.unitConfig.RequiresMountsFor  = [ "/data/media" ];
    systemd.services.radarr-rootfolders.unitConfig.RequiresMountsFor  = [ "/data/media" ];
    systemd.services.lidarr-rootfolders.unitConfig.RequiresMountsFor  = [ "/data/media" ];
    systemd.services.jellyfin-libraries.unitConfig.RequiresMountsFor  = [ "/data/media" ];
    systemd.services.podman-audiobookshelf.unitConfig.RequiresMountsFor = [ "/data/media" ];
    systemd.services.podman-shelfarr.unitConfig.RequiresMountsFor     = [ "/data/media" ];
    systemd.services.podman-filebrowser.unitConfig.RequiresMountsFor  = [ "/data/media" "/data/photos" ];
    systemd.services.immich-server.unitConfig.RequiresMountsFor       = [ "/data/photos" ];

    # --- Data directories ---
    systemd.tmpfiles.rules = [
      "d /data                      0755 root  root  -"
      "d /data/media                0775 root  media -"
      "d /data/media/tv             0775 root  media -"
      "d /data/media/movies         0775 root  media -"
      "d /data/media/music          0775 root  media -"
      "d /data/media/books          0777 root  media -"
      "d /downloads                 0775 root  media -"
      "d /downloads/usenet          0775 root  media -"
      "d /data/photos               0775 root  media -"
      "d /data/.state/services      0775 root  media -"
      "d /data/media/audiobooks               0777 root  media -"
      # Container state dirs
      "d /var/lib/audiobookshelf             0775 root  media -"
      "d /var/lib/audiobookshelf/config      0775 root  media -"
      "d /var/lib/audiobookshelf/metadata    0775 root  media -"
      "d /var/lib/shelfarr                   0755 root  root  -"

      "d /var/lib/filebrowser       0775 root  media -"
      "d /var/lib/decluttarr        0755 root  root  -"
      "d /var/lib/decluttarr/config 0755 root  root  -"
      "d /var/lib/recyclarr              0700 root  root  -"
      # Observability
      "d /var/lib/sabnzbd-exporter       0700 root  root  -"
    ];

    # --- Sops secrets ---
    # All secrets live in Secrets/secrets.yaml.
    # Before first build, populate them with:
    #
    #   sops ~/Dots/Secrets/secrets.yaml
    #
    # Add each key as a plain string (generate with: od -An -tx1 -N16 /dev/urandom | tr -d ' \n'):
    #   sonarr-api-key: "<32 hex chars>"
    #   radarr-api-key: "<32 hex chars>"
    #   lidarr-api-key: "<32 hex chars>"
    #   prowlarr-api-key: "<32 hex chars>"
    #   jellyseerr-api-key: "<32 hex chars>"
    #   sabnzbd-api-key: "<32 hex chars>"
    #   sabnzbd-nzb-key: "<32 hex chars>"
    #   jellyfin-api-key: "<32 hex chars>"
    #   jellyfin-admin-password: "<your chosen password>"
    #   cloudflare-tunnel: "<full credentials JSON from Cloudflare dashboard>"
    sops.secrets."sonarr-api-key"           = {};
    sops.secrets."radarr-api-key"           = {};
    sops.secrets."lidarr-api-key"           = {};
    sops.secrets."prowlarr-api-key"         = {};
    sops.secrets."jellyseerr-api-key"       = {};
    # audiobookshelf-api-key: declare here + add to homepage-env once you have the key from ABS Settings → API Keys
    sops.secrets."sabnzbd-api-key"              = {};
    sops.secrets."sabnzbd-nzb-key"              = {};
    sops.secrets."sabnzbd-username"             = {};
    sops.secrets."sabnzbd-password"             = {};
    sops.secrets."usenet/frugalusenet/username"    = {};
    sops.secrets."usenet/frugalusenet/password"    = {};
    sops.secrets."usenet/newshosting/username"     = {};
    sops.secrets."usenet/newshosting/password"     = {};
    sops.secrets."indexer-api-keys/Miatrix"        = {};
    sops.secrets."indexer-api-keys/NZBGeek"        = {};
    sops.secrets."indexer-api-keys/NZBPlanet"      = {};
    sops.secrets."jellyfin-api-key"         = {};
    sops.secrets."jellyfin-admin-password"  = {};
    sops.secrets."cloudflare-tunnel"        = {};
    sops.secrets."mullvad-wg-private-key"       = { mode = "0400"; };
    sops.secrets."grafana-admin-password"       = { owner = "grafana"; };
    sops.secrets."admin-username"           = {};
    sops.secrets."admin-password"           = {};
    # Private half of the dedicated Asgard→Eclipse key. Public half lives in
    # Eclipse's /storage/.ssh/authorized_keys (imperative — see Claude/eclipse.md).
    sops.secrets."eclipse-ssh-key"          = { mode = "0400"; };

    # Kernel UDP buffer tuning for smooth streaming over Tailscale
    boot.kernel.sysctl = {
      "net.core.rmem_max"           = lib.mkDefault 26214400;
      "net.core.wmem_max"           = lib.mkDefault 26214400;
      "net.core.netdev_max_backlog" = lib.mkDefault 5000;
    };

  };
}
