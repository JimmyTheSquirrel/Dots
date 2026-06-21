{ self, inputs, ... }: {

  flake.nixosModules.server = { config, pkgs, lib, activeUser, ... }:
  let
    # ── Glance YAML config (no secrets — reads Prometheus which has no auth) ──
    # Runs as native systemd service (not container) so server-stats widget
    # can read host CPU/memory/disk directly from /proc and /sys.
    glanceConfig = pkgs.writeText "glance.yml" ''
      server:
        port: 8888

      document:
        head: |
          <script>
          (() => {
            const q = 'node_filesystem_free_bytes{mountpoint="/data"} / 1073741824 or label_replace(sum(rate(node_network_receive_bytes_total{device=~"enp.*|wlp.*"}[15s])) / 125000, "stat", "download", "", "") or label_replace(sum(rate(node_network_transmit_bytes_total{device=~"enp.*|wlp.*"}[15s])) / 125000, "stat", "upload", "", "")';
            const url = 'http://localhost:9090/api/v1/query?query=' + encodeURIComponent(q);
            setInterval(async () => {
              const el = document.querySelector('.widget-type-custom-api .widget-content');
              if (!el) return;
              try {
                const resp = await fetch(url);
                const data = await resp.json();
                const r = data.data.result;
                if (!r || r.length < 3) return;
                const disk = Math.round(parseFloat(r[0].value[1]));
                const down = parseFloat(r[1].value[1]).toFixed(1);
                const up = parseFloat(r[2].value[1]).toFixed(1);
                el.innerHTML =
                  '<p class="size-h4"><span class="color-subtext">Disk /data:</span> <span class="color-primary">' + disk + ' GB</span> free</p>' +
                  '<p class="size-h4"><span class="color-subtext">Download:</span> <span class="color-primary">' + down + ' Mbps</span></p>' +
                  '<p class="size-h4"><span class="color-subtext">Upload:</span> <span class="color-primary">' + up + ' Mbps</span></p>';
              } catch(e) {}
            }, 5000);
          })();
          </script>
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
            .ygg-widget::before {
              content: "";
              display: block;
              width: 100%;
              height: 200px;
              margin-bottom: 8px;
              background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 400'%3E%3Cdefs%3E%3CradialGradient id='bg' cx='50%25' cy='45%25' r='42%25'%3E%3Cstop offset='0%25' stop-color='hsla(160,30%25,25%25,0.12)'/%3E%3Cstop offset='100%25' stop-color='hsla(160,30%25,15%25,0)'/%3E%3C/radialGradient%3E%3CradialGradient id='canopy' cx='50%25' cy='40%25' r='35%25'%3E%3Cstop offset='0%25' stop-color='hsla(140,50%25,40%25,0.18)'/%3E%3Cstop offset='70%25' stop-color='hsla(140,40%25,30%25,0.08)'/%3E%3Cstop offset='100%25' stop-color='hsla(140,30%25,25%25,0)'/%3E%3C/radialGradient%3E%3C/defs%3E%3Ccircle cx='200' cy='190' r='160' fill='url(%23bg)'/%3E%3Cg fill='none' stroke='hsla(160,35%25,55%25,0.35)' stroke-width='1.5'%3E%3Ccircle cx='200' cy='190' r='158'/%3E%3Ccircle cx='200' cy='190' r='150'/%3E%3C/g%3E%3Cg fill='hsla(160,40%25,60%25,0.45)' font-family='serif' font-size='14' font-weight='bold'%3E%3Ctext x='200' y='38' text-anchor='middle'%3E%E1%9A%A0%20%E1%9A%B1%20%E1%9A%A6%20%E1%9A%B2%20%E1%9A%A8%20%E1%9A%B7%20%E1%9A%A2%E1%9A%B3%20%E1%9A%BE%20%E1%9A%A9%3C/text%3E%3Ctext transform='translate(355,100) rotate(72)' text-anchor='middle'%3E%E1%9A%B1%E1%9A%A6%E1%9A%B2%E1%9A%A8%E1%9A%B7%3C/text%3E%3Ctext transform='translate(370,220) rotate(90)' text-anchor='middle'%3E%E1%9A%A2%E1%9A%B3%E1%9A%BE%E1%9A%A9%E1%9A%A0%3C/text%3E%3Ctext transform='translate(330,330) rotate(115)' text-anchor='middle'%3E%E1%9A%B1%E1%9A%A6%E1%9A%B7%E1%9A%A8%E1%9A%B2%3C/text%3E%3Ctext x='200' y='370' text-anchor='middle'%3E%E1%9A%BE%20%E1%9A%A9%20%E1%9A%A0%20%E1%9A%B1%20%E1%9A%A6%20%E1%9A%B2%20%E1%9A%A8%20%E1%9A%B7%20%E1%9A%A2%3C/text%3E%3Ctext transform='translate(70,330) rotate(-115)' text-anchor='middle'%3E%E1%9A%B3%E1%9A%BE%E1%9A%A9%E1%9A%A0%E1%9A%B1%3C/text%3E%3Ctext transform='translate(30,220) rotate(-90)' text-anchor='middle'%3E%E1%9A%A6%E1%9A%B2%E1%9A%A8%E1%9A%B7%E1%9A%A2%3C/text%3E%3Ctext transform='translate(45,100) rotate(-72)' text-anchor='middle'%3E%E1%9A%B3%E1%9A%BE%E1%9A%A9%E1%9A%A0%E1%9A%B1%3C/text%3E%3C/g%3E%3Cg fill='none' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M200 310 L200 160' stroke='hsla(30,30%25,45%25,0.7)' stroke-width='7'/%3E%3Cpath d='M196 310 L196 165' stroke='hsla(30,25%25,35%25,0.3)' stroke-width='2'/%3E%3Cpath d='M204 310 L204 165' stroke='hsla(30,25%25,35%25,0.3)' stroke-width='2'/%3E%3Cpath d='M200 260 Q175 240 140 225' stroke='hsla(30,28%25,42%25,0.65)' stroke-width='4.5'/%3E%3Cpath d='M200 260 Q225 240 260 225' stroke='hsla(30,28%25,42%25,0.65)' stroke-width='4.5'/%3E%3Cpath d='M200 235 Q168 215 125 195' stroke='hsla(30,28%25,42%25,0.6)' stroke-width='3.5'/%3E%3Cpath d='M200 235 Q232 215 275 195' stroke='hsla(30,28%25,42%25,0.6)' stroke-width='3.5'/%3E%3Cpath d='M200 210 Q178 190 145 170' stroke='hsla(30,28%25,42%25,0.55)' stroke-width='3'/%3E%3Cpath d='M200 210 Q222 190 255 170' stroke='hsla(30,28%25,42%25,0.55)' stroke-width='3'/%3E%3Cpath d='M200 190 Q185 170 160 148' stroke='hsla(30,25%25,40%25,0.5)' stroke-width='2.5'/%3E%3Cpath d='M200 190 Q215 170 240 148' stroke='hsla(30,25%25,40%25,0.5)' stroke-width='2.5'/%3E%3Cpath d='M200 175 Q200 150 200 120' stroke='hsla(30,25%25,40%25,0.5)' stroke-width='2.5'/%3E%3Cpath d='M140 225 Q125 218 108 215' stroke='hsla(30,22%25,38%25,0.45)' stroke-width='2'/%3E%3Cpath d='M260 225 Q275 218 292 215' stroke='hsla(30,22%25,38%25,0.45)' stroke-width='2'/%3E%3Cpath d='M125 195 Q108 185 90 178' stroke='hsla(30,22%25,38%25,0.4)' stroke-width='1.8'/%3E%3Cpath d='M275 195 Q292 185 310 178' stroke='hsla(30,22%25,38%25,0.4)' stroke-width='1.8'/%3E%3Cpath d='M145 170 Q130 158 115 150' stroke='hsla(30,22%25,38%25,0.4)' stroke-width='1.5'/%3E%3Cpath d='M255 170 Q270 158 285 150' stroke='hsla(30,22%25,38%25,0.4)' stroke-width='1.5'/%3E%3Cpath d='M160 148 Q148 138 135 130' stroke='hsla(30,20%25,36%25,0.35)' stroke-width='1.3'/%3E%3Cpath d='M240 148 Q252 138 265 130' stroke='hsla(30,20%25,36%25,0.35)' stroke-width='1.3'/%3E%3Cpath d='M140 225 Q130 230 118 228' stroke='hsla(30,22%25,38%25,0.35)' stroke-width='1.5'/%3E%3Cpath d='M260 225 Q270 230 282 228' stroke='hsla(30,22%25,38%25,0.35)' stroke-width='1.5'/%3E%3Cpath d='M125 195 Q115 200 102 198' stroke='hsla(30,20%25,36%25,0.3)' stroke-width='1.3'/%3E%3Cpath d='M275 195 Q285 200 298 198' stroke='hsla(30,20%25,36%25,0.3)' stroke-width='1.3'/%3E%3C/g%3E%3Ccircle cx='200' cy='155' r='62' fill='url(%23canopy)'/%3E%3Cg fill='hsla(140,45%25,35%25,0.22)' stroke='hsla(140,40%25,48%25,0.28)' stroke-width='0.8'%3E%3Cpath d='M200 102 Q210 112 222 118 Q210 118 200 126 Q190 118 178 118 Q190 112 200 102Z'/%3E%3Cpath d='M178 112 Q188 122 200 128 Q188 128 178 136 Q168 128 156 128 Q168 122 178 112Z'/%3E%3Cpath d='M222 112 Q232 122 244 128 Q232 128 222 136 Q212 128 200 128 Q212 122 222 112Z'/%3E%3Cpath d='M158 126 Q168 136 180 142 Q168 142 158 150 Q148 142 136 142 Q148 136 158 126Z'/%3E%3Cpath d='M242 126 Q252 136 264 142 Q252 142 242 150 Q232 142 220 142 Q232 136 242 126Z'/%3E%3Cpath d='M140 144 Q150 154 162 160 Q150 160 140 168 Q130 160 118 160 Q130 154 140 144Z'/%3E%3Cpath d='M260 144 Q270 154 282 160 Q270 160 260 168 Q250 160 238 160 Q250 154 260 144Z'/%3E%3Cpath d='M165 109 Q175 119 187 125 Q175 125 165 133 Q155 125 143 125 Q155 119 165 109Z'/%3E%3Cpath d='M235 109 Q245 119 257 125 Q245 125 235 133 Q225 125 213 125 Q225 119 235 109Z'/%3E%3Cpath d='M200 89 Q212 99 226 105 Q212 105 200 115 Q188 105 174 105 Q188 99 200 89Z'/%3E%3Cpath d='M185 95 Q195 105 207 111 Q195 111 185 119 Q175 111 163 111 Q175 105 185 95Z'/%3E%3Cpath d='M215 95 Q225 105 237 111 Q225 111 215 119 Q205 111 193 111 Q205 105 215 95Z'/%3E%3Cpath d='M148 134 Q158 144 170 150 Q158 150 148 158 Q138 150 126 150 Q138 144 148 134Z'/%3E%3Cpath d='M252 134 Q262 144 274 150 Q262 150 252 158 Q242 150 230 150 Q242 144 252 134Z'/%3E%3Cpath d='M125 162 Q135 172 147 178 Q135 178 125 186 Q115 178 103 178 Q115 172 125 162Z'/%3E%3Cpath d='M275 162 Q285 172 297 178 Q285 178 275 186 Q265 178 253 178 Q265 172 275 162Z'/%3E%3Cpath d='M108 182 Q118 192 130 198 Q118 198 108 206 Q98 198 86 198 Q98 192 108 182Z'/%3E%3Cpath d='M292 182 Q302 192 314 198 Q302 198 292 206 Q282 198 270 198 Q282 192 292 182Z'/%3E%3Cpath d='M118 199 Q128 209 140 215 Q128 215 118 223 Q108 215 96 215 Q108 209 118 199Z'/%3E%3Cpath d='M282 199 Q292 209 304 215 Q292 215 282 223 Q272 215 260 215 Q272 209 282 199Z'/%3E%3Cpath d='M145 119 Q155 129 167 135 Q155 135 145 143 Q135 135 123 135 Q135 129 145 119Z'/%3E%3Cpath d='M255 119 Q265 129 277 135 Q265 135 255 143 Q245 135 233 135 Q245 129 255 119Z'/%3E%3Cpath d='M135 152 Q145 162 157 168 Q145 168 135 176 Q125 168 113 168 Q125 162 135 152Z'/%3E%3Cpath d='M265 152 Q275 162 287 168 Q275 168 265 176 Q255 168 243 168 Q255 162 265 152Z'/%3E%3Cpath d='M115 172 Q125 182 137 188 Q125 188 115 196 Q105 188 93 188 Q105 182 115 172Z'/%3E%3Cpath d='M285 172 Q295 182 307 188 Q295 188 285 196 Q275 188 263 188 Q275 182 285 172Z'/%3E%3Cpath d='M90 160 Q100 170 112 176 Q100 176 90 184 Q80 176 68 176 Q80 170 90 160Z'/%3E%3Cpath d='M310 160 Q320 170 332 176 Q320 176 310 184 Q300 176 288 176 Q300 170 310 160Z'/%3E%3Cpath d='M115 132 Q125 142 137 148 Q125 148 115 156 Q105 148 93 148 Q105 142 115 132Z'/%3E%3Cpath d='M285 132 Q295 142 307 148 Q295 148 285 156 Q275 148 263 148 Q275 142 285 132Z'/%3E%3Cpath d='M135 112 Q145 122 157 128 Q145 128 135 136 Q125 128 113 128 Q125 122 135 112Z'/%3E%3Cpath d='M265 112 Q275 122 287 128 Q275 128 265 136 Q255 128 243 128 Q255 122 265 112Z'/%3E%3Cpath d='M200 80 Q210 90 222 96 Q210 96 200 104 Q190 96 178 96 Q190 90 200 80Z'/%3E%3C/g%3E%3Cg fill='none' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M200 310 Q170 315 138 325 Q115 332 88 328 Q65 322 50 330' stroke='hsla(30,30%25,40%25,0.6)' stroke-width='3.5'/%3E%3Cpath d='M200 310 Q230 315 262 325 Q285 332 312 328 Q335 322 350 330' stroke='hsla(30,30%25,40%25,0.6)' stroke-width='3.5'/%3E%3Cpath d='M195 305 Q165 312 130 320 Q108 325 82 318' stroke='hsla(30,25%25,38%25,0.5)' stroke-width='2.5'/%3E%3Cpath d='M205 305 Q235 312 270 320 Q292 325 318 318' stroke='hsla(30,25%25,38%25,0.5)' stroke-width='2.5'/%3E%3Cpath d='M88 328 Q75 325 62 328 Q55 332 45 338' stroke='hsla(30,25%25,36%25,0.4)' stroke-width='2'/%3E%3Cpath d='M312 328 Q325 325 338 328 Q345 332 355 338' stroke='hsla(30,25%25,36%25,0.4)' stroke-width='2'/%3E%3Cpath d='M138 325 Q128 330 115 340' stroke='hsla(30,25%25,36%25,0.4)' stroke-width='2'/%3E%3Cpath d='M262 325 Q272 330 285 340' stroke='hsla(30,25%25,36%25,0.4)' stroke-width='2'/%3E%3Cpath d='M130 320 Q118 322 105 330 Q98 336 88 345' stroke='hsla(30,22%25,34%25,0.35)' stroke-width='1.8'/%3E%3Cpath d='M270 320 Q282 322 295 330 Q302 336 312 345' stroke='hsla(30,22%25,34%25,0.35)' stroke-width='1.8'/%3E%3Cpath d='M82 318 Q68 312 58 315 Q50 320 42 328' stroke='hsla(30,22%25,34%25,0.35)' stroke-width='1.8'/%3E%3Cpath d='M318 318 Q332 312 342 315 Q350 320 358 328' stroke='hsla(30,22%25,34%25,0.35)' stroke-width='1.8'/%3E%3Cpath d='M192 308 Q178 318 162 335 Q155 345 145 355' stroke='hsla(30,22%25,34%25,0.3)' stroke-width='1.5'/%3E%3Cpath d='M208 308 Q222 318 238 335 Q245 345 255 355' stroke='hsla(30,22%25,34%25,0.3)' stroke-width='1.5'/%3E%3Cpath d='M50 330 Q42 328 35 332' stroke='hsla(30,20%25,32%25,0.3)' stroke-width='1.3'/%3E%3Cpath d='M350 330 Q358 328 365 332' stroke='hsla(30,20%25,32%25,0.3)' stroke-width='1.3'/%3E%3Cpath d='M200 315 Q200 330 198 345 Q196 355 200 360' stroke='hsla(30,22%25,34%25,0.3)' stroke-width='1.5'/%3E%3Cpath d='M88 328 Q80 335 72 345 Q68 350 60 358' stroke='hsla(30,20%25,32%25,0.28)' stroke-width='1.3'/%3E%3Cpath d='M312 328 Q320 335 328 345 Q332 350 340 358' stroke='hsla(30,20%25,32%25,0.28)' stroke-width='1.3'/%3E%3C/g%3E%3Cg fill='none' stroke='hsla(160,35%25,55%25,0.2)' stroke-width='0.6'%3E%3Cpath d='M200 310 Q180 312 165 318 Q155 322 150 330 Q148 338 155 342 Q165 345 175 340 Q182 335 185 325 Q188 318 200 310Z'/%3E%3Cpath d='M200 310 Q220 312 235 318 Q245 322 250 330 Q252 338 245 342 Q235 345 225 340 Q218 335 215 325 Q212 318 200 310Z'/%3E%3C/g%3E%3Cg fill='hsla(160,40%25,50%25,0.15)' stroke='hsla(160,35%25,55%25,0.25)' stroke-width='0.5'%3E%3Cpath d='M180 190 L190 185 L200 190 L190 195Z'/%3E%3Cpath d='M200 190 L210 185 L220 190 L210 195Z'/%3E%3Cpath d='M190 195 L200 190 L210 195 L200 200Z'/%3E%3C/g%3E%3C/svg%3E");
              background-repeat: no-repeat;
              background-position: center;
              background-size: contain;
              opacity: 0.8;
              filter: drop-shadow(0 0 12px hsla(160, 50%, 45%, 0.25));
              transition: opacity 0.3s ease, filter 0.3s ease;
            }
            .ygg-widget:hover::before {
              opacity: 1;
              filter: drop-shadow(0 0 18px hsla(160, 55%, 50%, 0.4));
            }

            /* ── Bookmarks styling ── */
            .widget-type-bookmarks .bookmarks-group .title {
              letter-spacing: 0.05em;
            }

            /* ── Subtle divider between widget sections ── */
            .column-full .widget + .widget {
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
          </style>

      theme:
        positive-color: hsl(142, 72%, 39%)
        negative-color: hsl(0, 84%, 60%)

      pages:
        # ════════════════════════════════════════════════════════════════════
        # PAGE 1 — Asgard (services + links)
        # ════════════════════════════════════════════════════════════════════
        - name: Asgard
          columns:
            - size: small
              widgets:
                - type: bookmarks
                  title: Links
                  groups:
                    - title: Watch & Browse
                      links:
                        - title: Jellyfin
                          url: http://asgard:8096
                        - title: Jellyseerr
                          url: http://asgard:5055
                        - title: Immich
                          url: http://asgard:2283
                        - title: Audiobookshelf
                          url: http://asgard:13378
                    - title: Downloads
                      links:
                        - title: SABnzbd
                          url: http://asgard:8080
                        - title: Prowlarr
                          url: http://asgard:9696
                    - title: Arr Stack
                      links:
                        - title: Sonarr
                          url: http://asgard:8989
                        - title: Radarr
                          url: http://asgard:7878
                        - title: Lidarr
                          url: http://asgard:8686
                        - title: Shelfarr
                          url: http://asgard:5056
                    - title: Management
                      links:
                        - title: FileBrowser
                          url: http://asgard:8081
                        - title: Headscale UI
                          url: http://asgard:8443
                        - title: Grafana
                          url: http://asgard:3001

            - size: full
              widgets:
                - type: server-stats
                  servers:
                    - type: local
                      name: Asgard
                      hide-mountpoints-by-default: true
                      mountpoints:
                        "/data":
                          name: Data
                          hide: false

                - type: custom-api
                  title: System Info
                  cache: 5s
                  url: http://localhost:9090/api/v1/query
                  parameters:
                    query: node_filesystem_free_bytes{mountpoint="/data"} / 1073741824 or label_replace(sum(rate(node_network_receive_bytes_total{device=~"enp.*|wlp.*"}[15s])) / 125000, "stat", "download", "", "") or label_replace(sum(rate(node_network_transmit_bytes_total{device=~"enp.*|wlp.*"}[15s])) / 125000, "stat", "upload", "", "")
                  template: |
                    {{ $disk := printf "%.0f" (.JSON.Float "data.result.0.value.1") }}
                    {{ $down := printf "%.1f" (.JSON.Float "data.result.1.value.1") }}
                    {{ $up := printf "%.1f" (.JSON.Float "data.result.2.value.1") }}
                    <p class="size-h4"><span class="color-subtext">Disk /data:</span> <span class="color-primary">{{ $disk }} GB</span> free</p>
                    <p class="size-h4"><span class="color-subtext">Download:</span> <span class="color-primary">{{ $down }} Mbps</span></p>
                    <p class="size-h4"><span class="color-subtext">Upload:</span> <span class="color-primary">{{ $up }} Mbps</span></p>

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
                  title: Arr Stack
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
                  title: Management
                  cache: 1m
                  sites:
                    - title: FileBrowser
                      url: http://asgard:8081
                      icon: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/filebrowser.svg
                    - title: Prometheus
                      url: http://asgard:9090
                      icon: sh:prometheus
                    - title: Loki
                      url: http://asgard:3100/ready
                      icon: sh:loki
                    - title: Headscale
                      url: http://asgard:8085/health
                      icon: sh:headscale
                    - title: Grafana
                      url: http://asgard:3001
                      icon: sh:grafana

            - size: small
              widgets:
                - type: clock
                  hour-format: 12h

                - type: custom-api
                  title: Yggdrasil Network
                  title-url: http://asgard:8443
                  css-class: ygg-widget
                  cache: 15s
                  url: http://localhost:8085/api/v1/node
                  headers:
                    Authorization: Bearer lUSP-6K.ZsUeNDkPEE7BOScNsi29L0T2J1nmoMYC
                  template: |
                    <style>
                      .hs-online {
                        width: 8px;
                        height: 8px;
                        border-radius: 50%;
                        background-color: hsl(142, 72%, 39%);
                        display: inline-block;
                        margin-left: 4px;
                        vertical-align: middle;
                      }
                      .hs-offline {
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
                      {{ range .JSON.Array "nodes" }}
                      <li>
                        <div class="flex items-center gap-10">
                          <div class="grow flex items-center gap-8">
                            <span class="size-h4 block text-truncate color-primary">
                              {{ .String "givenName" }}
                            </span>
                            {{ if .Bool "online" }}
                              <span class="hs-online" data-popover-type="text" data-popover-text="Online"></span>
                            {{ else }}
                              <span class="hs-offline" data-popover-type="text" data-popover-text="Offline - Last seen {{ .String "lastSeen" }}"></span>
                            {{ end }}
                          </div>
                          <span class="size-h5 color-subtext">{{ .String "ipAddresses.0" }}</span>
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
            host_whitelist = "asgard,asgard.tailb54b82.ts.net,100.119.193.77,host.containers.internal";
            inet_exposure = 4;
            x_frame_options = 0;
            web_color = "Night";
            web_compact = true;
            web_fullscreen = true;
            web_tabbed = true;
          };
          servers = [
            {
              name = "FrugalUsenet";
              host = "aunews.frugalusenet.com";
              port = 563;
              username._secret = config.sops.secrets."usenet/frugalusenet/username".path;
              password._secret = config.sops.secrets."usenet/frugalusenet/password".path;
              connections = 200;
              ssl = true;
              priority = 0;
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
#   Sonarr: WEB-1080p + WEB-2160p (TV is web-sourced)
#   Radarr: Remux-1080p + Remux-2160p (Remux → Bluray → WEB, best first)
# This fixes grab issues like "only getting Redux" — proper CF scoring applied.
# ══════════════════════════════════════════════════════════════════════════════

    # ── Missing content search ─────────────────────────────────────────────────
    # Radarr: daily search for all monitored movies without files.
    # Persistent = true → runs immediately on boot if the 4am window was missed.
    systemd.services.radarr-missing-search = {
      description = "Search all missing monitored movies in Radarr";
      after    = [ "radarr.service" ];
      requires = [ "radarr.service" ];
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

    # Sets Jellyseerr's default Radarr quality profile to "Remux + WEB 1080p"
    # (created by Recyclarr). Runs 12min after boot so Recyclarr (5min) has
    # had time to create the profile first. Idempotent — safe to re-run.
    systemd.services.seerr-radarr-profile = {
      description = "Set Jellyseerr default Radarr profile to Remux + WEB 1080p";
      after    = [ "seerr.service" "seerr-setup.service" "radarr.service" "network.target" ];
      wants    = [ "seerr.service" "seerr-setup.service" "radarr.service" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
      };
      script = ''
        set -euo pipefail
        SEERR="http://localhost:5055"
        RADARR="http://localhost:7878"
        COOKIE="/tmp/seerr-radarr-profile-cookie"
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        ADMIN_PASS=$(cat ${config.sops.secrets."jellyfin-admin-password".path})

        # Wait up to 2min for Jellyseerr
        for i in $(seq 1 24); do
          if curl -sf "$SEERR/api/v1/status" > /dev/null 2>&1; then break; fi
          echo "Waiting for Jellyseerr... ($i/24)"
          sleep 5
        done

        # Find the "Remux + WEB 1080p" profile ID in Radarr
        PROFILE_ID=$(curl -s -H "X-Api-Key: $RADARR_KEY" "$RADARR/api/v3/qualityprofile" | \
          jq -r '.[] | select(.name == "Remux + WEB 1080p") | .id')

        if [ -z "$PROFILE_ID" ]; then
          echo "Remux + WEB 1080p profile not found in Radarr — Recyclarr may not have run yet." >&2
          exit 1
        fi
        echo "Found Radarr profile: Remux + WEB 1080p (ID: $PROFILE_ID)"

        # Log into Jellyseerr (session cookie required for settings endpoints)
        LOGIN_CODE=$(curl -s -c "$COOKIE" -X POST \
          -H "Content-Type: application/json" \
          -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\"}" \
          -w "%{http_code}" -o /dev/null \
          "$SEERR/api/v1/auth/jellyfin")
        [ "$LOGIN_CODE" = "200" ] || [ "$LOGIN_CODE" = "201" ] || \
          { echo "Jellyseerr login failed (HTTP $LOGIN_CODE)" >&2; exit 1; }

        # Get current Radarr instance config and check if profile is already correct
        RADARR_CFG=$(curl -s -b "$COOKIE" "$SEERR/api/v1/settings/radarr")
        INSTANCE_ID=$(echo "$RADARR_CFG" | jq -r '.[0].id')
        CURRENT_PROFILE=$(echo "$RADARR_CFG" | jq -r '.[0].activeProfileId')

        if [ "$CURRENT_PROFILE" = "$PROFILE_ID" ]; then
          echo "Jellyseerr already using correct profile — nothing to do."
          rm -f "$COOKIE"
          exit 0
        fi

        # Update the profile
        UPDATED=$(echo "$RADARR_CFG" | jq --argjson pid "$PROFILE_ID" \
          '.[0] | .activeProfileId = $pid | .activeProfileName = "Remux + WEB 1080p" | del(.id)')
        curl -sf -b "$COOKIE" -X PUT \
          -H "Content-Type: application/json" \
          -d "$UPDATED" \
          "$SEERR/api/v1/settings/radarr/$INSTANCE_ID" > /dev/null

        rm -f "$COOKIE"
        echo "Jellyseerr Radarr profile updated to Remux + WEB 1080p (ID: $PROFILE_ID)"
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
      description = "Set Jellyseerr default Sonarr profile to WEB-1080p";
      after    = [ "seerr.service" "seerr-setup.service" "sonarr.service" "network.target" ];
      wants    = [ "seerr.service" "seerr-setup.service" "sonarr.service" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
      };
      script = ''
        set -euo pipefail
        SEERR="http://localhost:5055"
        SONARR="http://localhost:8989"
        COOKIE="/tmp/seerr-sonarr-profile-cookie"
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        ADMIN_PASS=$(cat ${config.sops.secrets."jellyfin-admin-password".path})

        for i in $(seq 1 24); do
          if curl -sf "$SEERR/api/v1/status" > /dev/null 2>&1; then break; fi
          echo "Waiting for Jellyseerr... ($i/24)"
          sleep 5
        done

        PROFILE_ID=$(curl -s -H "X-Api-Key: $SONARR_KEY" "$SONARR/api/v3/qualityprofile" | \
          jq -r '.[] | select(.name == "WEB-1080p") | .id')

        if [ -z "$PROFILE_ID" ]; then
          echo "WEB-1080p profile not found in Sonarr — Recyclarr may not have run yet." >&2
          exit 1
        fi
        echo "Found Sonarr profile: WEB-1080p (ID: $PROFILE_ID)"

        LOGIN_CODE=$(curl -s -c "$COOKIE" -X POST \
          -H "Content-Type: application/json" \
          -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\"}" \
          -w "%{http_code}" -o /dev/null \
          "$SEERR/api/v1/auth/jellyfin")
        [ "$LOGIN_CODE" = "200" ] || [ "$LOGIN_CODE" = "201" ] || \
          { echo "Jellyseerr login failed (HTTP $LOGIN_CODE)" >&2; exit 1; }

        SONARR_CFG=$(curl -s -b "$COOKIE" "$SEERR/api/v1/settings/sonarr")
        INSTANCE_ID=$(echo "$SONARR_CFG" | jq -r '.[0].id')
        CURRENT_PROFILE=$(echo "$SONARR_CFG" | jq -r '.[0].activeProfileId')

        if [ "$CURRENT_PROFILE" = "$PROFILE_ID" ]; then
          echo "Jellyseerr already using correct Sonarr profile — nothing to do."
          rm -f "$COOKIE"
          exit 0
        fi

        UPDATED=$(echo "$SONARR_CFG" | jq --argjson pid "$PROFILE_ID" \
          '.[0] | .activeProfileId = $pid | .activeProfileName = "WEB-1080p"
               | .activeAnimeProfileId = $pid | .activeAnimeProfileName = "WEB-1080p"
               | del(.id)')
        curl -sf -b "$COOKIE" -X PUT \
          -H "Content-Type: application/json" \
          -d "$UPDATED" \
          "$SEERR/api/v1/settings/sonarr/$INSTANCE_ID" > /dev/null

        rm -f "$COOKIE"
        echo "Jellyseerr Sonarr profile updated to WEB-1080p (ID: $PROFILE_ID)"
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
        cat > /var/lib/recyclarr/recyclarr.yml << EOF
sonarr:
  sonarr-main:
    base_url: http://localhost:8989
    api_key: $SONARR_KEY
    include:
      - template: sonarr-quality-definition-series
      - template: sonarr-v4-quality-profile-web-1080p
      - template: sonarr-v4-custom-formats-web-1080p
      - template: sonarr-v4-quality-profile-web-2160p
      - template: sonarr-v4-custom-formats-web-2160p
radarr:
  radarr-main:
    base_url: http://localhost:7878
    api_key: $RADARR_KEY
    include:
      - template: radarr-quality-definition-movie
      - template: radarr-quality-profile-remux-web-1080p
      - template: radarr-custom-formats-remux-web-1080p
      - template: radarr-quality-profile-remux-web-2160p
      - template: radarr-custom-formats-remux-web-2160p
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
        Environment = "RECYCLARR_APP_DATA=/var/lib/recyclarr";
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

    # --- Headscale (self-hosted Tailscale control plane) ---
    # Replaces Tailscale cloud. All devices auth against this server.
    # Accessible via Cloudflare tunnel at hs.bifrost-vault.com.
    # Manage from any machine: headscale -u rock nodes list
    services.headscale = {
      enable = true;
      port = 8085;
      address = "0.0.0.0";
      settings = {
        server_url = "https://hs.bifrost-vault.com";
        prefixes = {
          v4 = "100.64.0.0/10";
          v6 = "fd7a:115c:a1e0::/48";
        };
        dns = {
          base_domain = "bifrost.net";
          magic_dns = true;
          nameservers.global = [ "1.1.1.1" "9.9.9.9" ];
        };
        # Disable key expiry — devices stay connected even if Asgard is down
        disable_check_updates = true;
      };
    };

    # Headscale CLI available system-wide for management
    environment.systemPackages = [ pkgs.headscale pkgs.kitty.terminfo ];

    # --- Headscale UI (web admin panel) ---
    # headscale-admin by GoodiesHQ — supports Headscale 0.27+ API.
    # Port 8443 — Nginx reverse proxy serves both UI and API on same origin (avoids CORS).
    # / → headscale-admin container (8444), /api/ → headscale (8085)
    virtualisation.oci-containers.containers.headscale-admin = {
      image = "docker.io/goodieshq/headscale-admin:latest";
      ports = [ "127.0.0.1:8444:80" ];
    };

    services.nginx = {
      enable = true;
      virtualHosts."headscale-ui" = {
        listen = [{ addr = "0.0.0.0"; port = 8443; }];
        locations."/" = {
          return = "302 /admin/";
        };
        locations."/admin/" = {
          proxyPass = "http://127.0.0.1:8444/admin/";
        };
        locations."/api/" = {
          proxyPass = "http://127.0.0.1:8085/api/";
          extraConfig = ''
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
          '';
        };
      };
    };

    # --- Tailscale (client — connects to our Headscale) ---
    services.tailscale = {
      enable = true;
      openFirewall = true;
      extraUpFlags = [
        "--login-server" "https://hs.bifrost-vault.com"
      ];
    };

    services.cloudflared = {
      enable = true;
      tunnels = {
        "804d54a8-e7ad-4f34-812d-3052cf862c47" = {
          credentialsFile = config.sops.secrets."cloudflare-tunnel".path;
          default = "http_status:404";
          ingress = {
            "hs.bifrost-vault.com"       = "http://localhost:8085";
            "jellyfin.bifrost-vault.com"  = "http://localhost:8096";
            "requests.bifrost-vault.com"  = "http://localhost:5055";
            "photos.bifrost-vault.com"    = "http://localhost:2283";
          };
        };
      };
    };

    # TODO: Mullvad VPN kill switch for SABnzbd — deferred.
    # vpn-confinement (nixflix.vpn) works at the network namespace level but DNS
    # resolution inside the sandbox fails: the 100.64.0.0/10 accessibleFrom route
    # (needed for Tailscale return traffic) intercepts Mullvad's CGNAT DNS
    # (100.64.0.55), and SABnzbd's glibc can't reach any alternative DNS through
    # the tunnel from inside the systemd sandbox. /etc/hosts bypass was confirmed
    # to work at the Python level but SABnzbd still reports "Server name does not
    # resolve" — root cause not yet identified. Resume investigation later.


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
            # ── Disk /data (bar gauge: used / free / total) ──
            {
              id = 4; type = "bargauge"; title = "Disk /data";
              gridPos = { h = 4; w = 12; x = 12; y = 4; };
              datasource = "Prometheus";
              targets = [
                {
                  refId = "A"; datasource = "Prometheus";
                  expr = ''node_filesystem_size_bytes{mountpoint="/data"} - node_filesystem_avail_bytes{mountpoint="/data"}'';
                  legendFormat = "Used";
                }
                {
                  refId = "B"; datasource = "Prometheus";
                  expr = ''node_filesystem_avail_bytes{mountpoint="/data"}'';
                  legendFormat = "Free";
                }
                {
                  refId = "C"; datasource = "Prometheus";
                  expr = ''node_filesystem_size_bytes{mountpoint="/data"}'';
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
    networking.firewall.allowedTCPPorts = [ 8085 ]; # Headscale



    # DNS inside the VPN namespace (SABnzbd's sandbox) fails due to routing
    # conflicts. Bypass it entirely for the usenet server — /etc/hosts is read
    # first (nsswitch: files before dns), so getaddrinfo() never touches DNS.
    # IPs confirmed reachable via the Mullvad tunnel on port 563.
    networking.hosts = {
      "45.125.247.68"  = [ "aunews.frugalusenet.com" ];
      "45.125.247.108" = [ "aunews.frugalusenet.com" ];
    };

    # --- Shared media group (GID 1001) ---
    # All service users and containers use this group for /data/media access.
    users.groups.media = { gid = 1001; };
    users.users.${activeUser}.extraGroups = [ "media" ];
    users.users.jellyfin.extraGroups = [ "media" ];

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
    sops.secrets."indexer-api-keys/Miatrix"        = {};
    sops.secrets."indexer-api-keys/NZBGeek"        = {};
    sops.secrets."indexer-api-keys/NZBPlanet"      = {};
    sops.secrets."jellyfin-api-key"         = {};
    sops.secrets."jellyfin-admin-password"  = {};
    sops.secrets."cloudflare-tunnel"        = {};
    sops.secrets."mullvad-private-key"          = { mode = "0400"; };
    sops.secrets."grafana-admin-password"       = { owner = "grafana"; };
    sops.secrets."admin-username"           = {};
    sops.secrets."admin-password"           = {};

    # Kernel UDP buffer tuning for smooth streaming over Tailscale
    boot.kernel.sysctl = {
      "net.core.rmem_max"           = lib.mkDefault 26214400;
      "net.core.wmem_max"           = lib.mkDefault 26214400;
      "net.core.netdev_max_backlog" = lib.mkDefault 5000;
    };

  };
}
