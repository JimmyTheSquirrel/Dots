{ self, inputs, ... }: {
  flake.nixosModules.rain-effect = { pkgs, activeUser, ... }:
  let
    # ── C source: transparent Wayland layer-shell GLSL rain overlay ───────────
    # Sits on the wlr-layer-shell BOTTOM layer — above the wallpaper (skwd-wall),
    # below all windows. Completely independent of skwd-wall; changing wallpaper
    # while rain is active has no effect on the overlay.
    rainC = ''
      #define _POSIX_C_SOURCE 200809L
      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>
      #include <unistd.h>
      #include <signal.h>
      #include <time.h>

      #include <wayland-client.h>
      #include <wayland-egl.h>
      #include <EGL/egl.h>
      #include <GLES2/gl2.h>

      #include "wlr-layer-shell-client.h"

      #define MAX_OUTPUTS 8

      static volatile int running = 1;

      // ── Types ──────────────────────────────────────────────────────────────

      struct output {
          struct wl_output *wl_output;
          int done;
      };

      struct screen {
          struct output                *out;
          struct wl_surface            *surface;
          struct zwlr_layer_surface_v1 *layer_surface;
          struct wl_egl_window         *egl_window;
          EGLSurface                    egl_surface;
          int                           configured;
          uint32_t                      width, height;
      };

      // ── Globals ────────────────────────────────────────────────────────────

      static struct wl_display          *display;
      static struct wl_compositor       *compositor;
      static struct zwlr_layer_shell_v1 *layer_shell;

      static struct output outputs[MAX_OUTPUTS];
      static int           n_outputs = 0;
      static struct screen screens[MAX_OUTPUTS];
      static int           n_screens = 0;

      static EGLDisplay egl_dpy;
      static EGLContext egl_ctx;
      static EGLConfig  egl_cfg;

      static GLuint shader_program;
      static GLint  loc_time, loc_resolution, loc_pos;
      static GLuint vbo;

      // ── GLSL: rain streaks transparent overlay ─────────────────────────────
      // Background is fully transparent (alpha=0). Only the rain drops are
      // visible, so the wallpaper shows through underneath.

      static const char *vert_src =
          "attribute vec2 pos;\n"
          "void main() { gl_Position = vec4(pos, 0.0, 1.0); }\n";

      static const char *frag_src =
          "precision highp float;\n"
          "uniform float u_time;\n"
          "uniform vec2  u_resolution;\n"
          "\n"
          "float rng(vec2 p) {\n"
          "    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);\n"
          "}\n"
          "\n"
          "// One layer of rain: grid of falling streaks with randomised\n"
          "// speed, length, brightness, and a slight directional lean.\n"
          "float rainLayer(vec2 uv, float t, float density, float speed, float lean) {\n"
          "    float aspect = u_resolution.x / u_resolution.y;\n"
          "    vec2  grid   = vec2(density * aspect, density);\n"
          "    vec2  cell   = floor(uv * grid);\n"
          "    vec2  f      = fract(uv * grid);\n"
          "    float offset = rng(cell);\n"
          "    float spd    = speed * (0.7 + rng(cell + 5.0)  * 0.6);\n"
          "    float bright = 0.4  + rng(cell + 10.0) * 0.6;\n"
          "    float len    = 0.06 + rng(cell + 15.0) * 0.18;\n"
          "    float w      = 0.05 + rng(cell + 20.0) * 0.08;\n"
          "    float xLean  = lean * f.y;\n"
          "    float y      = fract(t * spd + offset);\n"
          "    float xMask  = smoothstep(0.5 - w, 0.5, f.x + xLean)\n"
          "                 * smoothstep(0.5 + w, 0.5, f.x + xLean);\n"
          "    float yDist  = f.y - y;\n"
          "    float yMask  = smoothstep(0.0, 0.01, yDist)\n"
          "                 * (1.0 - smoothstep(len * 0.4, len, yDist));\n"
          "    return xMask * yMask * bright;\n"
          "}\n"
          "\n"
          "void main() {\n"
          "    vec2  uv = gl_FragCoord.xy / u_resolution;\n"
          "    uv.y = 1.0 - uv.y;\n"
          "    float t = u_time * 0.4;\n"
          "    float r = 0.0;\n"
          "    // Three depth layers: far (faint/dense), mid, close (bright/sparse)\n"
          "    r += rainLayer(uv, t * 0.55, 42.0, 0.7, -0.10) * 0.30;\n"
          "    r += rainLayer(uv, t * 0.75, 28.0, 1.0, -0.12) * 0.55;\n"
          "    r += rainLayer(uv, t * 1.00, 16.0, 1.4, -0.15) * 0.80;\n"
          "    r = clamp(r, 0.0, 1.0);\n"
          "    vec3 color = vec3(0.68, 0.84, 1.0);\n"
          "    gl_FragColor = vec4(color, r * 0.60);\n"
          "}\n";

      // ── Shader helpers ─────────────────────────────────────────────────────

      static GLuint compile_shader(GLenum type, const char *src) {
          GLuint s = glCreateShader(type);
          glShaderSource(s, 1, &src, NULL);
          glCompileShader(s);
          GLint ok;
          glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
          if (!ok) {
              char log[512];
              glGetShaderInfoLog(s, sizeof(log), NULL, log);
              fprintf(stderr, "rain-overlay shader error: %s\n", log);
              exit(1);
          }
          return s;
      }

      static GLuint link_program(void) {
          GLuint p = glCreateProgram();
          GLuint v = compile_shader(GL_VERTEX_SHADER,   vert_src);
          GLuint f = compile_shader(GL_FRAGMENT_SHADER, frag_src);
          glAttachShader(p, v);
          glAttachShader(p, f);
          glLinkProgram(p);
          GLint ok;
          glGetProgramiv(p, GL_LINK_STATUS, &ok);
          if (!ok) {
              char log[512];
              glGetProgramInfoLog(p, sizeof(log), NULL, log);
              fprintf(stderr, "rain-overlay link error: %s\n", log);
              exit(1);
          }
          glDeleteShader(v);
          glDeleteShader(f);
          return p;
      }

      // ── EGL setup ─────────────────────────────────────────────────────────

      static void egl_init(void) {
          egl_dpy = eglGetDisplay((EGLNativeDisplayType)display);
          eglInitialize(egl_dpy, NULL, NULL);
          eglBindAPI(EGL_OPENGL_ES_API);

          EGLint attribs[] = {
              EGL_SURFACE_TYPE,    EGL_WINDOW_BIT,
              EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
              EGL_RED_SIZE,   8,
              EGL_GREEN_SIZE, 8,
              EGL_BLUE_SIZE,  8,
              EGL_ALPHA_SIZE, 8,   // required for transparent overlay
              EGL_NONE
          };
          EGLint n;
          eglChooseConfig(egl_dpy, attribs, &egl_cfg, 1, &n);

          EGLint ctx_attribs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
          egl_ctx = eglCreateContext(egl_dpy, egl_cfg, EGL_NO_CONTEXT, ctx_attribs);
      }

      // ── Layer surface callbacks ────────────────────────────────────────────

      static void ls_configure(void *data,
          struct zwlr_layer_surface_v1 *ls,
          uint32_t serial, uint32_t w, uint32_t h)
      {
          struct screen *scr = data;
          zwlr_layer_surface_v1_ack_configure(ls, serial);
          scr->width  = w;
          scr->height = h;
          if (!scr->configured) {
              scr->egl_window  = wl_egl_window_create(scr->surface, w, h);
              scr->egl_surface = eglCreateWindowSurface(egl_dpy, egl_cfg,
                  (EGLNativeWindowType)scr->egl_window, NULL);
              scr->configured = 1;
          } else {
              wl_egl_window_resize(scr->egl_window, w, h, 0, 0);
          }
          wl_surface_commit(scr->surface);
      }

      static void ls_closed(void *data, struct zwlr_layer_surface_v1 *ls) {
          running = 0;
      }

      static const struct zwlr_layer_surface_v1_listener ls_listener = {
          .configure = ls_configure,
          .closed    = ls_closed,
      };

      // ── Output callbacks ───────────────────────────────────────────────────

      static void out_geometry(void *d, struct wl_output *o,
          int32_t x, int32_t y, int32_t pw, int32_t ph,
          int32_t sub, const char *mk, const char *mo, int32_t tr) {}
      static void out_mode(void *d, struct wl_output *o,
          uint32_t flags, int32_t w, int32_t h, int32_t r) {}
      static void out_done(void *data, struct wl_output *o) {
          ((struct output *)data)->done = 1;
      }
      static void out_scale(void *d, struct wl_output *o, int32_t f) {}
      static void out_name(void *d, struct wl_output *o, const char *name) {}
      static void out_description(void *d, struct wl_output *o, const char *desc) {}

      static const struct wl_output_listener output_listener = {
          .geometry    = out_geometry,
          .mode        = out_mode,
          .done        = out_done,
          .scale       = out_scale,
          .name        = out_name,
          .description = out_description,
      };

      // ── Registry ───────────────────────────────────────────────────────────

      static void reg_global(void *data, struct wl_registry *reg,
          uint32_t name, const char *iface, uint32_t ver)
      {
          if (strcmp(iface, wl_compositor_interface.name) == 0) {
              compositor  = wl_registry_bind(reg, name, &wl_compositor_interface, 4);
          } else if (strcmp(iface, zwlr_layer_shell_v1_interface.name) == 0) {
              layer_shell = wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface, 1);
          } else if (strcmp(iface, wl_output_interface.name) == 0 && n_outputs < MAX_OUTPUTS) {
              struct output *out = &outputs[n_outputs++];
              out->wl_output = wl_registry_bind(reg, name, &wl_output_interface, 4);
              wl_output_add_listener(out->wl_output, &output_listener, out);
          }
      }

      static void reg_global_remove(void *data, struct wl_registry *reg, uint32_t name) {}

      static const struct wl_registry_listener reg_listener = {
          .global        = reg_global,
          .global_remove = reg_global_remove,
      };

      // ── Screen setup ───────────────────────────────────────────────────────

      static void create_screen(struct output *out) {
          struct screen *scr = &screens[n_screens++];
          scr->out        = out;
          scr->configured = 0;
          scr->surface    = wl_compositor_create_surface(compositor);

          // Empty input region: all pointer/keyboard events pass through
          struct wl_region *input = wl_compositor_create_region(compositor);
          wl_surface_set_input_region(scr->surface, input);
          wl_region_destroy(input);

          scr->layer_surface = zwlr_layer_shell_v1_get_layer_surface(
              layer_shell, scr->surface, out->wl_output,
              ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM, "rain-overlay");

          // Full-screen, no exclusive zone (doesn't push other surfaces)
          zwlr_layer_surface_v1_set_size(scr->layer_surface, 0, 0);
          zwlr_layer_surface_v1_set_anchor(scr->layer_surface,
              ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP    |
              ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
              ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT   |
              ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
          zwlr_layer_surface_v1_set_exclusive_zone(scr->layer_surface, -1);
          zwlr_layer_surface_v1_set_keyboard_interactivity(
              scr->layer_surface,
              ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);

          zwlr_layer_surface_v1_add_listener(scr->layer_surface, &ls_listener, scr);
          wl_surface_commit(scr->surface);
      }

      // ── Render ─────────────────────────────────────────────────────────────

      static void render(struct screen *scr, float t) {
          eglMakeCurrent(egl_dpy, scr->egl_surface, scr->egl_surface, egl_ctx);
          glViewport(0, 0, scr->width, scr->height);
          glClearColor(0.0f, 0.0f, 0.0f, 0.0f); // fully transparent clear
          glClear(GL_COLOR_BUFFER_BIT);
          glEnable(GL_BLEND);
          glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
          glUseProgram(shader_program);
          glUniform1f(loc_time, t);
          glUniform2f(loc_resolution, (float)scr->width, (float)scr->height);
          glBindBuffer(GL_ARRAY_BUFFER, vbo);
          glEnableVertexAttribArray(loc_pos);
          glVertexAttribPointer(loc_pos, 2, GL_FLOAT, GL_FALSE, 0, NULL);
          glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
          eglSwapBuffers(egl_dpy, scr->egl_surface);
      }

      // ── Time helper ────────────────────────────────────────────────────────

      static double monotime(void) {
          struct timespec ts;
          clock_gettime(CLOCK_MONOTONIC, &ts);
          return ts.tv_sec + ts.tv_nsec * 1e-9;
      }

      // ── Main ───────────────────────────────────────────────────────────────

      static void sighandler(int sig) { running = 0; }

      int main(void) {
          signal(SIGTERM, sighandler);
          signal(SIGINT,  sighandler);

          display = wl_display_connect(NULL);
          if (!display) {
              fputs("rain-overlay: cannot connect to Wayland display\n", stderr);
              return 1;
          }

          struct wl_registry *reg = wl_display_get_registry(display);
          wl_registry_add_listener(reg, &reg_listener, NULL);
          wl_display_roundtrip(display);
          wl_display_roundtrip(display); // second pass picks up output events

          if (!compositor || !layer_shell) {
              fputs("rain-overlay: compositor or zwlr_layer_shell_v1 not available\n", stderr);
              return 1;
          }

          egl_init();

          for (int i = 0; i < n_outputs; i++)
              create_screen(&outputs[i]);

          wl_display_roundtrip(display); // trigger configure events

          while (running) {
              int ready = 1;
              for (int i = 0; i < n_screens; i++)
                  if (!screens[i].configured) { ready = 0; break; }
              if (ready) break;
              wl_display_dispatch(display);
          }

          if (n_screens == 0) {
              fputs("rain-overlay: no screens configured\n", stderr);
              return 1;
          }

          // GL objects are shared across all EGL surfaces via the single context
          eglMakeCurrent(egl_dpy, screens[0].egl_surface, screens[0].egl_surface, egl_ctx);
          shader_program = link_program();
          loc_time       = glGetUniformLocation(shader_program, "u_time");
          loc_resolution = glGetUniformLocation(shader_program, "u_resolution");
          loc_pos        = glGetAttribLocation (shader_program, "pos");

          float quad[] = { -1.0f,-1.0f,  1.0f,-1.0f,  -1.0f,1.0f,  1.0f,1.0f };
          glGenBuffers(1, &vbo);
          glBindBuffer(GL_ARRAY_BUFFER, vbo);
          glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);

          double t0 = monotime();

          while (running) {
              if (wl_display_dispatch_pending(display) < 0) break;
              float t = (float)(monotime() - t0);
              for (int i = 0; i < n_screens; i++)
                  if (screens[i].configured)
                      render(&screens[i], t);
              wl_display_flush(display);
              usleep(16667); // ~60 fps
          }

          return 0;
      }
    '';

    # ── Compile the overlay binary inside Nix ────────────────────────────────

    rainOverlay = pkgs.stdenv.mkDerivation {
      pname   = "rain-overlay";
      version = "1.0";
      dontUnpack = true;

      nativeBuildInputs = [ pkgs.pkg-config pkgs.wayland-scanner ];
      buildInputs       = with pkgs; [ wayland mesa libGL ];

      buildPhase = ''
        cp ${pkgs.writeText "rain-overlay.c" rainC} rain-overlay.c

        # Generate wlr-layer-shell Wayland protocol bindings
        wayland-scanner client-header \
          < ${pkgs.wlr-protocols}/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml \
          > wlr-layer-shell-client.h
        wayland-scanner private-code \
          < ${pkgs.wlr-protocols}/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml \
          > wlr-layer-shell-protocol.c

        gcc rain-overlay.c wlr-layer-shell-protocol.c \
          -I. -O2 -std=c11 \
          $(pkg-config --cflags --libs wayland-client wayland-egl egl glesv2) \
          -lm -o rain-overlay
      '';

      installPhase = ''
        mkdir -p $out/bin
        cp rain-overlay $out/bin/rain-overlay
      '';
    };

    # ── Toggle script ─────────────────────────────────────────────────────────
    # Usage: rain-toggle          (toggles on/off)
    # Future: rain-toggle on/off  (explicit, for weather automation)

    rainToggle = pkgs.writeShellScriptBin "rain-toggle" ''
      PIDFILE="''${XDG_RUNTIME_DIR:-/tmp}/rain-overlay.pid"

      _start() {
        ${rainOverlay}/bin/rain-overlay &
        echo $! > "$PIDFILE"
        notify-send -t 2000 -i weather-showers "Rain Effect" "On" 2>/dev/null || true
      }

      _stop() {
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
        notify-send -t 2000 -i weather-clear "Rain Effect" "Off" 2>/dev/null || true
      }

      _running() {
        [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
      }

      case "''${1:-toggle}" in
        on)     _running || _start ;;
        off)    _running && _stop  ;;
        toggle) _running && _stop || _start ;;
        *)      echo "Usage: rain-toggle [on|off|toggle]" >&2; exit 1 ;;
      esac
    '';

  in {
    home-manager.users.${activeUser} = {
      home.packages = [ rainOverlay rainToggle ];
    };
  };
}
