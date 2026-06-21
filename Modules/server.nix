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
              background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 400'%3E%3Cdefs%3E%3CradialGradient id='bg' cx='50%25' cy='45%25' r='42%25'%3E%3Cstop offset='0%25' stop-color='hsla(160,30%25,25%25,0.12)'/%3E%3Cstop offset='100%25' stop-color='hsla(160,30%25,15%25,0)'/%3E%3C/radialGradient%3E%3CradialGradient id='canopy' cx='50%25' cy='42%25' r='38%25'%3E%3Cstop offset='0%25' stop-color='hsla(140,50%25,40%25,0.2)'/%3E%3Cstop offset='60%25' stop-color='hsla(140,40%25,30%25,0.1)'/%3E%3Cstop offset='100%25' stop-color='hsla(140,30%25,25%25,0)'/%3E%3C/radialGradient%3E%3C/defs%3E%3Ccircle cx='200' cy='190' r='160' fill='url(%23bg)'/%3E%3Cg fill='none' stroke='hsla(160,35%25,55%25,0.35)' stroke-width='1.5'%3E%3Ccircle cx='200' cy='190' r='158'/%3E%3Ccircle cx='200' cy='190' r='150'/%3E%3C/g%3E%3Cg fill='hsla(160,40%25,60%25,0.45)' font-family='serif' font-size='14' font-weight='bold'%3E%3Ctext x='200' y='38' text-anchor='middle'%3E%E1%9A%A0%20%E1%9A%B1%20%E1%9A%A6%20%E1%9A%B2%20%E1%9A%A8%20%E1%9A%B7%20%E1%9A%A2%E1%9A%B3%20%E1%9A%BE%20%E1%9A%A9%3C/text%3E%3Ctext transform='translate(355,100) rotate(72)' text-anchor='middle'%3E%E1%9A%B1%E1%9A%A6%E1%9A%B2%E1%9A%A8%E1%9A%B7%3C/text%3E%3Ctext transform='translate(370,220) rotate(90)' text-anchor='middle'%3E%E1%9A%A2%E1%9A%B3%E1%9A%BE%E1%9A%A9%E1%9A%A0%3C/text%3E%3Ctext transform='translate(330,330) rotate(115)' text-anchor='middle'%3E%E1%9A%B1%E1%9A%A6%E1%9A%B7%E1%9A%A8%E1%9A%B2%3C/text%3E%3Ctext x='200' y='370' text-anchor='middle'%3E%E1%9A%BE%20%E1%9A%A9%20%E1%9A%A0%20%E1%9A%B1%20%E1%9A%A6%20%E1%9A%B2%20%E1%9A%A8%20%E1%9A%B7%20%E1%9A%A2%3C/text%3E%3Ctext transform='translate(70,330) rotate(-115)' text-anchor='middle'%3E%E1%9A%B3%E1%9A%BE%E1%9A%A9%E1%9A%A0%E1%9A%B1%3C/text%3E%3Ctext transform='translate(30,220) rotate(-90)' text-anchor='middle'%3E%E1%9A%A6%E1%9A%B2%E1%9A%A8%E1%9A%B7%E1%9A%A2%3C/text%3E%3Ctext transform='translate(45,100) rotate(-72)' text-anchor='middle'%3E%E1%9A%B3%E1%9A%BE%E1%9A%A9%E1%9A%A0%E1%9A%B1%3C/text%3E%3C/g%3E%3Cg fill='none' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M200 310 C198 285 202 250 199 220 C197 195 201 175 200 158' stroke='hsla(30,30%25,45%25,0.7)' stroke-width='8'/%3E%3Cpath d='M196 310 C195 278 197 240 196 165' stroke='hsla(30,25%25,35%25,0.25)' stroke-width='2'/%3E%3Cpath d='M205 310 C206 282 204 248 205 165' stroke='hsla(30,25%25,35%25,0.25)' stroke-width='2'/%3E%3Cpath d='M199 268 C180 255 158 248 135 238 C118 230 105 228 92 222' stroke='hsla(30,28%25,42%25,0.65)' stroke-width='4'/%3E%3Cpath d='M155 242 C148 235 138 232 125 228' stroke='hsla(30,25%25,40%25,0.45)' stroke-width='2'/%3E%3Cpath d='M135 238 C128 242 118 248 108 252' stroke='hsla(30,25%25,40%25,0.4)' stroke-width='1.8'/%3E%3Cpath d='M92 222 C82 218 74 220 65 225' stroke='hsla(30,22%25,38%25,0.35)' stroke-width='1.3'/%3E%3Cpath d='M92 222 C88 215 82 208 75 205' stroke='hsla(30,22%25,38%25,0.35)' stroke-width='1.3'/%3E%3Cpath d='M201 258 C225 242 248 232 272 225 C290 220 305 218 315 212' stroke='hsla(30,28%25,42%25,0.6)' stroke-width='3.5'/%3E%3Cpath d='M258 228 C265 222 275 215 288 210' stroke='hsla(30,25%25,40%25,0.4)' stroke-width='1.8'/%3E%3Cpath d='M272 225 C278 232 285 238 295 240' stroke='hsla(30,25%25,40%25,0.38)' stroke-width='1.5'/%3E%3Cpath d='M315 212 C322 208 330 205 338 208' stroke='hsla(30,22%25,38%25,0.3)' stroke-width='1.2'/%3E%3Cpath d='M199 240 C175 225 148 212 122 198 C105 190 90 185 78 178' stroke='hsla(30,28%25,42%25,0.55)' stroke-width='3.5'/%3E%3Cpath d='M148 212 C140 208 130 198 118 192' stroke='hsla(30,25%25,40%25,0.4)' stroke-width='1.8'/%3E%3Cpath d='M122 198 C115 202 105 208 95 212' stroke='hsla(30,22%25,38%25,0.35)' stroke-width='1.5'/%3E%3Cpath d='M78 178 C70 175 62 178 55 182' stroke='hsla(30,20%25,36%25,0.3)' stroke-width='1.2'/%3E%3Cpath d='M78 178 C72 172 65 168 58 165' stroke='hsla(30,20%25,36%25,0.3)' stroke-width='1.2'/%3E%3Cpath d='M201 232 C228 215 255 200 280 188 C298 180 312 175 322 168' stroke='hsla(30,28%25,42%25,0.5)' stroke-width='3'/%3E%3Cpath d='M260 198 C268 192 278 185 290 180' stroke='hsla(30,25%25,40%25,0.38)' stroke-width='1.6'/%3E%3Cpath d='M280 188 C285 195 292 200 302 202' stroke='hsla(30,22%25,38%25,0.32)' stroke-width='1.3'/%3E%3Cpath d='M322 168 C328 162 335 158 342 160' stroke='hsla(30,20%25,36%25,0.28)' stroke-width='1.1'/%3E%3Cpath d='M200 218 C178 205 152 188 132 172 C118 160 108 152 98 142' stroke='hsla(30,28%25,42%25,0.5)' stroke-width='2.8'/%3E%3Cpath d='M152 188 C145 180 135 172 122 165' stroke='hsla(30,22%25,38%25,0.38)' stroke-width='1.5'/%3E%3Cpath d='M132 172 C125 178 115 182 105 185' stroke='hsla(30,22%25,38%25,0.32)' stroke-width='1.3'/%3E%3Cpath d='M98 142 C90 138 82 140 75 145' stroke='hsla(30,20%25,36%25,0.28)' stroke-width='1.1'/%3E%3Cpath d='M98 142 C92 135 85 128 80 125' stroke='hsla(30,20%25,36%25,0.25)' stroke-width='1'/%3E%3Cpath d='M200 205 C222 188 248 172 268 158 C282 148 292 140 298 132' stroke='hsla(30,28%25,42%25,0.45)' stroke-width='2.5'/%3E%3Cpath d='M248 172 C255 165 265 155 275 148' stroke='hsla(30,22%25,38%25,0.35)' stroke-width='1.4'/%3E%3Cpath d='M268 158 C275 162 282 168 290 170' stroke='hsla(30,22%25,38%25,0.3)' stroke-width='1.2'/%3E%3Cpath d='M298 132 C302 125 308 120 315 122' stroke='hsla(30,20%25,36%25,0.25)' stroke-width='1'/%3E%3Cpath d='M200 195 C185 178 168 158 155 142 C145 130 138 120 132 112' stroke='hsla(30,25%25,40%25,0.45)' stroke-width='2.2'/%3E%3Cpath d='M168 158 C160 152 150 142 140 135' stroke='hsla(30,22%25,38%25,0.35)' stroke-width='1.3'/%3E%3Cpath d='M155 142 C148 148 138 152 128 155' stroke='hsla(30,20%25,36%25,0.3)' stroke-width='1.1'/%3E%3Cpath d='M132 112 C125 108 118 110 112 115' stroke='hsla(30,18%25,34%25,0.25)' stroke-width='0.9'/%3E%3Cpath d='M200 178 C215 162 232 142 248 128 C258 120 268 115 275 108' stroke='hsla(30,25%25,40%25,0.42)' stroke-width='2'/%3E%3Cpath d='M232 142 C240 135 250 125 260 118' stroke='hsla(30,22%25,38%25,0.32)' stroke-width='1.2'/%3E%3Cpath d='M248 128 C252 135 258 140 265 142' stroke='hsla(30,20%25,36%25,0.28)' stroke-width='1'/%3E%3Cpath d='M275 108 C280 102 288 100 295 105' stroke='hsla(30,18%25,34%25,0.22)' stroke-width='0.9'/%3E%3Cpath d='M200 172 C198 155 195 135 192 118 C190 108 188 98 185 90' stroke='hsla(30,25%25,40%25,0.48)' stroke-width='2.5'/%3E%3Cpath d='M195 135 C188 128 178 122 170 118' stroke='hsla(30,22%25,38%25,0.35)' stroke-width='1.3'/%3E%3Cpath d='M192 118 C198 112 205 108 212 110' stroke='hsla(30,22%25,38%25,0.32)' stroke-width='1.2'/%3E%3Cpath d='M185 90 C182 82 178 78 172 80' stroke='hsla(30,18%25,34%25,0.25)' stroke-width='0.9'/%3E%3Cpath d='M185 90 C188 82 192 76 198 75' stroke='hsla(30,18%25,34%25,0.25)' stroke-width='0.9'/%3E%3C/g%3E%3Ccircle cx='198' cy='152' r='68' fill='url(%23canopy)'/%3E%3Cg fill='hsla(140,45%25,35%25,0.2)' stroke='hsla(140,40%25,48%25,0.25)' stroke-width='0.6'%3E%3Cpath d='M200 98 C206 106 208 116 203 118 C198 112 196 104 200 98Z'/%3E%3Cpath d='M192 85 C198 92 200 102 195 105 C190 98 188 90 192 85Z'/%3E%3Cpath d='M208 88 C202 96 200 105 206 108 C212 102 214 94 208 88Z'/%3E%3Cpath d='M185 92 C190 100 190 110 185 112 C180 106 180 98 185 92Z'/%3E%3Cpath d='M215 90 C210 98 210 108 215 110 C220 104 220 96 215 90Z'/%3E%3Cpath d='M178 102 C185 108 188 118 183 122 C176 116 174 108 178 102Z'/%3E%3Cpath d='M222 100 C215 106 212 116 218 120 C224 114 226 106 222 100Z'/%3E%3Cpath d='M168 112 C176 115 180 125 175 130 C167 125 164 118 168 112Z'/%3E%3Cpath d='M234 108 C226 112 222 122 228 126 C235 122 238 114 234 108Z'/%3E%3Cpath d='M158 125 C166 126 172 135 168 140 C160 137 154 130 158 125Z'/%3E%3Cpath d='M245 120 C237 122 232 132 237 136 C244 132 248 125 245 120Z'/%3E%3Cpath d='M148 138 C156 138 164 146 160 152 C152 150 144 144 148 138Z'/%3E%3Cpath d='M256 132 C248 134 242 142 247 148 C255 144 260 138 256 132Z'/%3E%3Cpath d='M138 152 C146 150 155 158 152 164 C144 162 134 158 138 152Z'/%3E%3Cpath d='M266 145 C258 144 250 152 254 158 C262 155 270 150 266 145Z'/%3E%3Cpath d='M128 165 C136 162 146 168 142 174 C134 172 124 170 128 165Z'/%3E%3Cpath d='M276 158 C268 156 258 164 262 170 C270 167 280 162 276 158Z'/%3E%3Cpath d='M118 178 C126 175 136 180 132 186 C124 184 114 182 118 178Z'/%3E%3Cpath d='M288 170 C280 168 270 176 274 182 C282 178 292 174 288 170Z'/%3E%3Cpath d='M108 192 C116 188 128 194 124 200 C116 198 104 196 108 192Z'/%3E%3Cpath d='M298 182 C290 180 280 188 284 194 C292 190 302 186 298 182Z'/%3E%3Cpath d='M100 205 C108 202 118 208 114 214 C106 212 96 210 100 205Z'/%3E%3Cpath d='M308 195 C300 193 290 200 294 206 C302 202 312 199 308 195Z'/%3E%3Cpath d='M95 218 C103 214 114 220 110 226 C102 224 91 222 95 218Z'/%3E%3Cpath d='M310 208 C302 206 292 214 296 220 C304 216 314 212 310 208Z'/%3E%3Cpath d='M88 230 C96 226 108 232 104 238 C96 236 84 234 88 230Z'/%3E%3Cpath d='M110 238 C118 235 128 240 124 246 C116 244 106 242 110 238Z'/%3E%3Cpath d='M295 225 C288 222 278 228 282 234 C290 230 298 228 295 225Z'/%3E%3Cpath d='M172 78 C176 85 175 94 170 96 C166 90 167 82 172 78Z'/%3E%3Cpath d='M198 74 C202 82 200 92 195 94 C192 86 194 78 198 74Z'/%3E%3Cpath d='M188 100 C194 106 195 116 190 119 C185 112 184 104 188 100Z'/%3E%3Cpath d='M212 98 C206 105 205 114 210 117 C216 110 216 102 212 98Z'/%3E%3Cpath d='M175 108 C182 112 184 122 179 126 C173 120 171 112 175 108Z'/%3E%3Cpath d='M228 105 C222 110 220 120 225 124 C230 118 232 110 228 105Z'/%3E%3Cpath d='M162 120 C170 122 174 132 169 136 C162 130 158 124 162 120Z'/%3E%3Cpath d='M240 115 C234 118 230 128 235 132 C242 126 244 120 240 115Z'/%3E%3Cpath d='M150 135 C158 134 165 142 162 148 C154 146 146 140 150 135Z'/%3E%3Cpath d='M252 128 C244 128 238 136 242 142 C250 138 256 132 252 128Z'/%3E%3Cpath d='M140 148 C148 146 156 152 153 158 C145 156 136 152 140 148Z'/%3E%3Cpath d='M264 140 C256 140 248 148 252 154 C260 150 268 144 264 140Z'/%3E%3Cpath d='M130 160 C138 157 148 162 145 168 C137 166 126 164 130 160Z'/%3E%3Cpath d='M274 152 C266 150 257 158 261 164 C269 160 278 156 274 152Z'/%3E%3Cpath d='M120 172 C128 168 138 174 134 180 C126 178 116 176 120 172Z'/%3E%3Cpath d='M285 164 C277 162 268 170 272 176 C280 172 289 168 285 164Z'/%3E%3Cpath d='M110 185 C118 182 128 188 124 194 C116 192 106 190 110 185Z'/%3E%3Cpath d='M295 176 C287 174 278 182 282 188 C290 184 299 180 295 176Z'/%3E%3Cpath d='M102 198 C110 195 120 200 116 206 C108 204 98 202 102 198Z'/%3E%3Cpath d='M305 188 C297 186 288 194 292 200 C300 196 309 192 305 188Z'/%3E%3Cpath d='M92 212 C100 208 112 214 108 220 C100 218 88 216 92 212Z'/%3E%3Cpath d='M315 200 C307 198 298 206 302 212 C310 208 319 204 315 200Z'/%3E%3Cpath d='M85 225 C93 222 104 228 100 234 C92 232 82 230 85 225Z'/%3E%3Cpath d='M318 212 C310 210 300 218 304 224 C312 220 322 216 318 212Z'/%3E%3Cpath d='M80 168 C86 164 95 170 92 175 C85 174 76 172 80 168Z'/%3E%3Cpath d='M322 160 C316 158 308 164 312 170 C318 166 326 163 322 160Z'/%3E%3Cpath d='M72 182 C78 178 88 184 85 189 C78 188 68 186 72 182Z'/%3E%3Cpath d='M332 172 C326 170 318 176 322 182 C328 178 336 175 332 172Z'/%3E%3Cpath d='M65 195 C72 192 82 198 78 203 C72 202 62 200 65 195Z'/%3E%3Cpath d='M338 185 C332 183 324 190 328 195 C334 192 342 188 338 185Z'/%3E%3Cpath d='M60 208 C66 205 76 210 72 215 C66 214 56 212 60 208Z'/%3E%3Cpath d='M342 198 C336 196 328 202 332 208 C338 204 346 202 342 198Z'/%3E%3Cpath d='M112 112 C118 108 126 114 122 118 C116 118 108 116 112 112Z'/%3E%3Cpath d='M295 105 C290 102 282 108 286 112 C292 110 298 108 295 105Z'/%3E%3Cpath d='M82 128 C88 124 96 130 92 134 C86 134 78 132 82 128Z'/%3E%3Cpath d='M315 118 C310 116 302 122 306 126 C312 124 318 122 315 118Z'/%3E%3Cpath d='M75 145 C82 142 90 148 86 152 C80 152 72 150 75 145Z'/%3E%3Cpath d='M330 138 C324 136 316 142 320 146 C326 144 334 142 330 138Z'/%3E%3C/g%3E%3Cg fill='none' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M200 310 C172 318 142 325 118 332 C95 338 72 335 52 340' stroke='hsla(30,30%25,40%25,0.6)' stroke-width='3.5'/%3E%3Cpath d='M200 310 C232 316 262 322 288 328 C310 332 332 328 352 335' stroke='hsla(30,30%25,40%25,0.6)' stroke-width='3.5'/%3E%3Cpath d='M195 306 C165 315 132 322 108 328 C88 332 68 325 52 320' stroke='hsla(30,25%25,38%25,0.5)' stroke-width='2.5'/%3E%3Cpath d='M206 306 C238 312 268 318 295 322 C318 325 338 320 355 315' stroke='hsla(30,25%25,38%25,0.5)' stroke-width='2.5'/%3E%3Cpath d='M118 332 C108 338 95 345 85 352' stroke='hsla(30,25%25,36%25,0.4)' stroke-width='2'/%3E%3Cpath d='M288 328 C298 334 308 342 318 350' stroke='hsla(30,25%25,36%25,0.4)' stroke-width='2'/%3E%3Cpath d='M52 340 C42 342 34 348 28 355' stroke='hsla(30,22%25,34%25,0.35)' stroke-width='1.5'/%3E%3Cpath d='M352 335 C360 338 368 344 375 352' stroke='hsla(30,22%25,34%25,0.35)' stroke-width='1.5'/%3E%3Cpath d='M108 328 C98 332 85 340 75 348' stroke='hsla(30,22%25,34%25,0.35)' stroke-width='1.8'/%3E%3Cpath d='M295 322 C305 326 318 335 328 345' stroke='hsla(30,22%25,34%25,0.35)' stroke-width='1.8'/%3E%3Cpath d='M52 320 C42 318 32 322 25 330' stroke='hsla(30,20%25,32%25,0.3)' stroke-width='1.3'/%3E%3Cpath d='M355 315 C362 312 372 318 378 325' stroke='hsla(30,20%25,32%25,0.3)' stroke-width='1.3'/%3E%3Cpath d='M192 308 C178 322 162 338 148 355' stroke='hsla(30,22%25,34%25,0.3)' stroke-width='1.5'/%3E%3Cpath d='M208 308 C222 320 238 335 252 352' stroke='hsla(30,22%25,34%25,0.3)' stroke-width='1.5'/%3E%3Cpath d='M200 315 C202 335 198 350 200 365' stroke='hsla(30,22%25,34%25,0.28)' stroke-width='1.5'/%3E%3Cpath d='M52 340 C48 335 42 332 35 335' stroke='hsla(30,18%25,30%25,0.25)' stroke-width='1'/%3E%3Cpath d='M352 335 C355 330 362 328 368 332' stroke='hsla(30,18%25,30%25,0.25)' stroke-width='1'/%3E%3C/g%3E%3Cg fill='none' stroke='hsla(160,35%25,55%25,0.2)' stroke-width='0.6'%3E%3Cpath d='M198 312 Q175 318 158 325 Q148 332 145 340 Q144 348 152 350 Q162 348 170 342 Q178 335 182 325 Q188 318 198 312Z'/%3E%3Cpath d='M202 312 Q225 316 242 322 Q252 328 256 336 Q258 344 250 347 Q240 346 232 340 Q224 332 218 324 Q212 316 202 312Z'/%3E%3C/g%3E%3Cg fill='hsla(160,40%25,50%25,0.15)' stroke='hsla(160,35%25,55%25,0.25)' stroke-width='0.5'%3E%3Cpath d='M180 190 L190 185 L200 190 L190 195Z'/%3E%3Cpath d='M200 190 L210 185 L220 190 L210 195Z'/%3E%3Cpath d='M190 195 L200 190 L210 195 L200 200Z'/%3E%3C/g%3E%3C/svg%3E");
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
