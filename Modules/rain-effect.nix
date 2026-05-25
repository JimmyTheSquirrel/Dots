{ self, inputs, ... }: {
  flake.nixosModules.rain-effect = { pkgs, activeUser, ... }:
  let
    shinePath = "${self}/Resources/Rain-Effect/drop-shine.png";

    # ── C source: single-pass refractive rain overlay ──────────────────────────
    # Computes rain normals + wallpaper refraction in one fragment shader pass.
    # No FBO needed — eliminates coordinate encoding/decoding complexity.
    # Drop simulation: "Heartfelt" by BigWings (CC BY-NC-SA 3.0)
    # Refraction technique: Codrops RainDrops (Lucas Bebber)
    rainC = ''
      #define _POSIX_C_SOURCE 200809L
      #define STB_IMAGE_IMPLEMENTATION
      #include <stb/stb_image.h>

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
      #define SHINE_PATH "${shinePath}"

      static volatile int running = 1;
      static volatile sig_atomic_t reload_flag = 0;

      // ── Wallpaper state ────────────────────────────────────────────────────
      static GLuint tex_wallpaper = 0;
      static float  wallpaper_ratio = 1.777f;

      // ── Shine texture ──────────────────────────────────────────────────────
      static GLuint tex_shine = 0;

      // ── Shader program ─────────────────────────────────────────────────────
      static GLuint prog = 0;
      static GLint  loc_time, loc_res, loc_wallpaper, loc_shine;
      static GLint  loc_texratio, loc_pos, loc_uv;

      static GLuint vbo;

      // ── Types ──────────────────────────────────────────────────────────────
      struct output { struct wl_output *wl_output; int done; };

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
      static struct output outputs[MAX_OUTPUTS]; static int n_outputs = 0;
      static struct screen screens[MAX_OUTPUTS]; static int n_screens  = 0;
      static EGLDisplay egl_dpy;
      static EGLContext egl_ctx;
      static EGLConfig  egl_cfg;

      // ── Vertex shader ──────────────────────────────────────────────────────
      static const char *vert_src =
          "attribute vec2 pos;\n"
          "attribute vec2 a_uv;\n"
          "varying vec2 v_uv;\n"
          "void main() {\n"
          "    gl_Position = vec4(pos, 0.0, 1.0);\n"
          "    v_uv = a_uv;\n"
          "}\n";

      // ── Fragment shader: rain normals + wallpaper refraction ───────────────
      // Drop functions: adapted from "Heartfelt" by BigWings (CC BY-NC-SA 3.0)
      // Refraction: adapted from Codrops RainDrops (Lucas Bebber)
      static const char *frag_src =
          "precision highp float;\n"
          "uniform float u_time;\n"
          "uniform vec2  u_resolution;\n"
          "uniform sampler2D u_wallpaper;\n"
          "uniform sampler2D u_shine;\n"
          "uniform float u_texRatio;\n"
          "varying vec2 v_uv;\n"
          "#define S(a,b,t) smoothstep(a,b,t)\n"
          "\n"
          "vec3 N13(float p){\n"
          "    vec3 p3=fract(vec3(p)*vec3(.1031,.11369,.13787));\n"
          "    p3+=dot(p3,p3.yzx+19.19);\n"
          "    return fract(vec3((p3.x+p3.y)*p3.z,(p3.x+p3.z)*p3.y,(p3.y+p3.z)*p3.x));\n"
          "}\n"
          "float N(float t){return fract(sin(t*12345.564)*7658.76);}\n"
          "float Saw(float b,float t){return S(0.,b,t)*S(1.,b,t);}\n"
          "\n"
          "vec2 DropLayer2(vec2 uv,float t){\n"
          "    vec2 UV=uv;\n"
          "    uv.y+=t*0.75;\n"
          "    vec2 a=vec2(3.,3.),grid=a*2.,id=floor(uv*grid);\n"
          "    float colShift=N(id.x);\n"
          "    uv.y+=colShift;\n"
          "    id=floor(uv*grid);\n"
          "    vec3 n=N13(id.x*35.2+id.y*2376.1);\n"
          "    vec2 st=fract(uv*grid)-vec2(.5,0.);\n"
          "    float x=n.x-.5;\n"
          "    float y=UV.y*20.+n.x*13.7;\n"
          "    float wiggle=sin(y+sin(y));\n"
          "    x+=wiggle*(.5-abs(x))*(n.z-.5);\n"
          "    x*=.7;\n"
          "    float ti=fract(t+n.z);\n"
          "    y=(Saw(.85,ti)-.5)*.9+.5;\n"
          "    vec2 p=vec2(x,y);\n"
          "    float d=length((st-p)*a.yx);\n"
          "    float mainDrop=S(.4,.0,d);\n"
          "    float r=sqrt(S(1.,y,st.y));\n"
          "    float cd=abs(st.x-x);\n"
          "    float trail=S(.23*r,.15*r*r,cd)*S(-.02,.02,st.y-y)*r*r;\n"
          "    y=UV.y+n.z*0.09;\n"
          "    float trail2=S(.2*r,.0,cd);\n"
          "    float droplets=max(0.,(sin(y*(1.-y)*120.)-st.y))*trail2*S(-.02,.02,st.y-y)*n.z;\n"
          "    return vec2(mainDrop+droplets*r*S(-.02,.02,st.y-(Saw(.85,ti)-.5)*.9+.5),trail);\n"
          "}\n"
          "\n"
          "float StaticDrops(vec2 uv,float t){\n"
          "    uv*=16.;\n"
          "    vec2 id=floor(uv);\n"
          "    uv=fract(uv)-.5;\n"
          "    vec3 n=N13(id.x*107.45+id.y*3543.654);\n"
          "    float d=length(uv-(n.xy-.5)*.7);\n"
          "    return S(.3,0.,d)*fract(n.z*10.)*Saw(.025,fract(t+n.z));\n"
          "}\n"
          "\n"
          "mat2 rot2(float a){float c=cos(a),s=sin(a);return mat2(c,-s,s,c);}\n"
          "\n"
          "vec2 Drops(vec2 uv,float t,float l0,float l1,float l2){\n"
          "    vec2 m1=DropLayer2(rot2(0.07)*uv,t)*l1;\n"
          "    float c=S(.05,0.9,m1.x);\n"
          "    return vec2(c,m1.y*l0);\n"
          "}\n"
          "\n"
          "// Map screen UV → wallpaper UV (cover/fill mode)\n"
          "vec2 wallUV(vec2 uv){\n"
          "    float sr=u_resolution.x/u_resolution.y;\n"
          "    if(sr>u_texRatio){\n"
          "        float f=u_texRatio/sr;\n"
          "        return vec2(uv.x, uv.y*f+(1.-f)*.5);\n"
          "    } else {\n"
          "        float f=sr/u_texRatio;\n"
          "        return vec2(uv.x*f+(1.-f)*.5, uv.y);\n"
          "    }\n"
          "}\n"
          "\n"
          "void main(){\n"
          "    float t=u_time*0.2;\n"
          "    float rain=0.48;\n"
          "    float sd=S(-.5,1.,rain)*2.;\n"
          "    float l1=S(.25,.75,rain);\n"
          "    float l2=S(.0,.5,rain);\n"
          "\n"
          "    vec2 uv=(gl_FragCoord.xy-0.5*u_resolution.xy)/u_resolution.y;\n"
          "    vec2 c=Drops(uv,t,sd,l1,l2);\n"
          "    float dropAlpha=c.x;\n"
          "    float trailAlpha=c.y;\n"
          "    // Glass drops: mostly transparent, specular highlight is the main visual cue\n"
          "    float alpha=clamp(dropAlpha*0.35+trailAlpha*0.02,0.,1.);\n"
          "    if(alpha<0.01){gl_FragColor=vec4(0.);return;}\n"
          "\n"
          "    vec2 screenUV=gl_FragCoord.xy/u_resolution.xy;\n"
          "    float e=1.5/u_resolution.y;\n"
          "    float nx=Drops(uv+vec2(e,0.),t,sd,l1,l2).x-dropAlpha;\n"
          "    float ny=Drops(uv+vec2(0.,e),t,sd,l1,l2).x-dropAlpha;\n"
          "    vec2 normal=vec2(nx,ny)*5.0;\n"
          "\n"
          "    vec2 refractUV=wallUV(clamp(screenUV+normal*0.006,0.,1.));\n"
          "    vec4 wall=texture2D(u_wallpaper,refractUV);\n"
          "    // Almost no tint — drop body shows refracted wallpaper, specular makes it visible\n"
          "    vec3 water=mix(wall.rgb,vec3(0.92,0.95,1.0),0.04);\n"
          "    vec4 shine=texture2D(u_shine,fract(v_uv*vec2(4.,2.)+normal*0.5));\n"
          "    float spec=shine.r*dropAlpha*0.85;\n"
          "    gl_FragColor=vec4(water+spec,alpha);\n"
          "}\n";

      // ── Shader helpers ─────────────────────────────────────────────────────
      static GLuint compile_shader(GLenum type, const char *src) {
          GLuint s = glCreateShader(type);
          glShaderSource(s, 1, &src, NULL);
          glCompileShader(s);
          GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
          if (!ok) {
              char log[512]; glGetShaderInfoLog(s, sizeof(log), NULL, log);
              fprintf(stderr, "rain-overlay shader error: %s\n", log); exit(1);
          }
          return s;
      }

      static GLuint link_program(void) {
          GLuint p = glCreateProgram();
          GLuint v = compile_shader(GL_VERTEX_SHADER,   vert_src);
          GLuint f = compile_shader(GL_FRAGMENT_SHADER, frag_src);
          glAttachShader(p, v); glAttachShader(p, f);
          glLinkProgram(p);
          GLint ok; glGetProgramiv(p, GL_LINK_STATUS, &ok);
          if (!ok) {
              char log[512]; glGetProgramInfoLog(p, sizeof(log), NULL, log);
              fprintf(stderr, "rain-overlay link error: %s\n", log); exit(1);
          }
          glDeleteShader(v); glDeleteShader(f);
          return p;
      }

      // ── Texture loading ────────────────────────────────────────────────────
      static GLuint load_texture(const char *path, float *out_ratio) {
          int w, h, ch;
          stbi_set_flip_vertically_on_load(1);
          unsigned char *data = stbi_load(path, &w, &h, &ch, 4);
          if (!data) {
              fprintf(stderr, "rain-overlay: failed to load: %s\n", path);
              return 0;
          }
          GLuint tex;
          glGenTextures(1, &tex);
          glBindTexture(GL_TEXTURE_2D, tex);
          glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
          stbi_image_free(data);
          if (out_ratio && h > 0) *out_ratio = (float)w / (float)h;
          return tex;
      }

      static void load_wallpaper(void) {
          const char *xdg = getenv("XDG_RUNTIME_DIR");
          if (!xdg) xdg = "/tmp";
          char pathfile[4096];
          snprintf(pathfile, sizeof(pathfile), "%s/rain-overlay.wallpaper", xdg);
          fprintf(stderr, "rain-overlay: reading wallpaper path from %s\n", pathfile);
          FILE *f = fopen(pathfile, "r");
          if (!f) { fprintf(stderr, "rain-overlay: wallpaper file not found\n"); return; }
          char path[4096] = {0};
          if (!fgets(path, sizeof(path), f)) { fclose(f); fprintf(stderr, "rain-overlay: wallpaper file empty\n"); return; }
          fclose(f);
          path[strcspn(path, "\n")] = 0;
          if (!path[0]) { fprintf(stderr, "rain-overlay: wallpaper path blank\n"); return; }
          fprintf(stderr, "rain-overlay: loading wallpaper: [%s]\n", path);

          if (tex_wallpaper) glDeleteTextures(1, &tex_wallpaper);
          tex_wallpaper = load_texture(path, &wallpaper_ratio);
          fprintf(stderr, "rain-overlay: tex_wallpaper=%u ratio=%.3f\n", tex_wallpaper, wallpaper_ratio);
      }

      // ── EGL setup ──────────────────────────────────────────────────────────
      static void egl_init(void) {
          egl_dpy = eglGetDisplay((EGLNativeDisplayType)display);
          eglInitialize(egl_dpy, NULL, NULL);
          eglBindAPI(EGL_OPENGL_ES_API);
          EGLint attribs[] = {
              EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
              EGL_RED_SIZE,8, EGL_GREEN_SIZE,8, EGL_BLUE_SIZE,8, EGL_ALPHA_SIZE,8, EGL_NONE
          };
          EGLint n; eglChooseConfig(egl_dpy, attribs, &egl_cfg, 1, &n);
          EGLint ctx_attribs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
          egl_ctx = eglCreateContext(egl_dpy, egl_cfg, EGL_NO_CONTEXT, ctx_attribs);
      }

      // ── Layer surface callbacks ─────────────────────────────────────────────
      static void ls_configure(void *data, struct zwlr_layer_surface_v1 *ls,
          uint32_t serial, uint32_t w, uint32_t h)
      {
          struct screen *scr = data;
          zwlr_layer_surface_v1_ack_configure(ls, serial);
          scr->width = w; scr->height = h;
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
      static void ls_closed(void *data, struct zwlr_layer_surface_v1 *ls){running=0;}
      static const struct zwlr_layer_surface_v1_listener ls_listener = {
          .configure=ls_configure, .closed=ls_closed,
      };

      // ── Output callbacks ───────────────────────────────────────────────────
      static void out_geometry(void*d,struct wl_output*o,int32_t x,int32_t y,
          int32_t pw,int32_t ph,int32_t sub,const char*mk,const char*mo,int32_t tr){}
      static void out_mode(void*d,struct wl_output*o,uint32_t f,int32_t w,int32_t h,int32_t r){}
      static void out_done(void*data,struct wl_output*o){((struct output*)data)->done=1;}
      static void out_scale(void*d,struct wl_output*o,int32_t f){}
      static void out_name(void*d,struct wl_output*o,const char*n){}
      static void out_description(void*d,struct wl_output*o,const char*desc){}
      static const struct wl_output_listener output_listener = {
          .geometry=out_geometry,.mode=out_mode,.done=out_done,
          .scale=out_scale,.name=out_name,.description=out_description,
      };

      // ── Registry ───────────────────────────────────────────────────────────
      static void reg_global(void*data,struct wl_registry*reg,
          uint32_t name,const char*iface,uint32_t ver)
      {
          if(strcmp(iface,wl_compositor_interface.name)==0)
              compositor=wl_registry_bind(reg,name,&wl_compositor_interface,4);
          else if(strcmp(iface,zwlr_layer_shell_v1_interface.name)==0)
              layer_shell=wl_registry_bind(reg,name,&zwlr_layer_shell_v1_interface,1);
          else if(strcmp(iface,wl_output_interface.name)==0&&n_outputs<MAX_OUTPUTS){
              struct output*out=&outputs[n_outputs++];
              out->wl_output=wl_registry_bind(reg,name,&wl_output_interface,4);
              wl_output_add_listener(out->wl_output,&output_listener,out);
          }
      }
      static void reg_global_remove(void*d,struct wl_registry*r,uint32_t n){}
      static const struct wl_registry_listener reg_listener={
          .global=reg_global,.global_remove=reg_global_remove,
      };

      // ── Screen setup ───────────────────────────────────────────────────────
      static void create_screen(struct output *out) {
          struct screen *scr = &screens[n_screens++];
          scr->out=out; scr->configured=0;
          scr->surface=wl_compositor_create_surface(compositor);
          struct wl_region *input=wl_compositor_create_region(compositor);
          wl_surface_set_input_region(scr->surface,input);
          wl_region_destroy(input);
          scr->layer_surface=zwlr_layer_shell_v1_get_layer_surface(
              layer_shell,scr->surface,out->wl_output,
              ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM,"rain-overlay");
          zwlr_layer_surface_v1_set_size(scr->layer_surface,0,0);
          zwlr_layer_surface_v1_set_anchor(scr->layer_surface,
              ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP|ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM|
              ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT|ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
          zwlr_layer_surface_v1_set_exclusive_zone(scr->layer_surface,-1);
          zwlr_layer_surface_v1_set_keyboard_interactivity(scr->layer_surface,
              ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
          zwlr_layer_surface_v1_add_listener(scr->layer_surface,&ls_listener,scr);
          wl_surface_commit(scr->surface);
      }

      // ── Render ─────────────────────────────────────────────────────────────
      static void render(struct screen *scr, float t) {
          eglMakeCurrent(egl_dpy, scr->egl_surface, scr->egl_surface, egl_ctx);
          glViewport(0, 0, scr->width, scr->height);
          glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
          glClear(GL_COLOR_BUFFER_BIT);

          if (tex_wallpaper == 0) { eglSwapBuffers(egl_dpy, scr->egl_surface); return; }

          glEnable(GL_BLEND);
          glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
          glUseProgram(prog);

          glUniform1f(loc_time, t);
          glUniform2f(loc_res, (float)scr->width, (float)scr->height);
          glUniform1f(loc_texratio, wallpaper_ratio);

          glActiveTexture(GL_TEXTURE0);
          glBindTexture(GL_TEXTURE_2D, tex_wallpaper);
          glUniform1i(loc_wallpaper, 0);

          glActiveTexture(GL_TEXTURE1);
          glBindTexture(GL_TEXTURE_2D, tex_shine);
          glUniform1i(loc_shine, 1);

          glBindBuffer(GL_ARRAY_BUFFER, vbo);
          glEnableVertexAttribArray(loc_pos);
          glVertexAttribPointer(loc_pos, 2, GL_FLOAT, GL_FALSE, 4*sizeof(float), (void*)0);
          glEnableVertexAttribArray(loc_uv);
          glVertexAttribPointer(loc_uv,  2, GL_FLOAT, GL_FALSE, 4*sizeof(float), (void*)(2*sizeof(float)));
          glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

          eglSwapBuffers(egl_dpy, scr->egl_surface);
      }

      // ── Time / signals ─────────────────────────────────────────────────────
      static double monotime(void) {
          struct timespec ts;
          clock_gettime(CLOCK_MONOTONIC, &ts);
          return ts.tv_sec + ts.tv_nsec * 1e-9;
      }
      static void sighandler(int sig)  { running = 0; }
      static void sigusr1(int sig)     { reload_flag = 1; }

      // ── Main ───────────────────────────────────────────────────────────────
      int main(void) {
          signal(SIGTERM, sighandler);
          signal(SIGINT,  sighandler);
          signal(SIGUSR1, sigusr1);

          display = wl_display_connect(NULL);
          if (!display) { fputs("rain-overlay: no Wayland display\n", stderr); return 1; }

          struct wl_registry *reg = wl_display_get_registry(display);
          wl_registry_add_listener(reg, &reg_listener, NULL);
          wl_display_roundtrip(display);
          wl_display_roundtrip(display);

          if (!compositor || !layer_shell) {
              fputs("rain-overlay: compositor or layer_shell not available\n", stderr);
              return 1;
          }

          egl_init();
          for (int i = 0; i < n_outputs; i++) create_screen(&outputs[i]);
          wl_display_roundtrip(display);

          while (running) {
              int ready = 1;
              for (int i = 0; i < n_screens; i++)
                  if (!screens[i].configured) { ready = 0; break; }
              if (ready) break;
              wl_display_dispatch(display);
          }

          if (n_screens == 0) { fputs("rain-overlay: no screens\n", stderr); return 1; }

          eglMakeCurrent(egl_dpy, screens[0].egl_surface, screens[0].egl_surface, egl_ctx);

          prog = link_program();
          loc_time      = glGetUniformLocation(prog, "u_time");
          loc_res       = glGetUniformLocation(prog, "u_resolution");
          loc_wallpaper = glGetUniformLocation(prog, "u_wallpaper");
          loc_shine     = glGetUniformLocation(prog, "u_shine");
          loc_texratio  = glGetUniformLocation(prog, "u_texRatio");
          loc_pos       = glGetAttribLocation (prog, "pos");
          loc_uv        = glGetAttribLocation (prog, "a_uv");

          // Interleaved VBO: vec2 pos + vec2 uv
          float quad[] = {
              -1.0f,-1.0f, 0.0f,0.0f,
               1.0f,-1.0f, 1.0f,0.0f,
              -1.0f, 1.0f, 0.0f,1.0f,
               1.0f, 1.0f, 1.0f,1.0f,
          };
          glGenBuffers(1, &vbo);
          glBindBuffer(GL_ARRAY_BUFFER, vbo);
          glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);

          tex_shine = load_texture(SHINE_PATH, NULL);
          load_wallpaper();

          double t0 = monotime();

          while (running) {
              if (wl_display_dispatch_pending(display) < 0) break;
              if (reload_flag) { reload_flag = 0; load_wallpaper(); }
              float t = (float)(monotime() - t0);
              for (int i = 0; i < n_screens; i++)
                  if (screens[i].configured) render(&screens[i], t);
              wl_display_flush(display);
              struct timespec ts = {0, 16667000};
              nanosleep(&ts, NULL);
          }
          return 0;
      }
    '';

    rainOverlay = pkgs.stdenv.mkDerivation {
      pname   = "rain-overlay";
      version = "2.1";
      dontUnpack = true;

      nativeBuildInputs = [ pkgs.pkg-config pkgs.wayland-scanner ];
      buildInputs = with pkgs; [ wayland wayland-protocols wlr-protocols mesa libGL stb ];

      buildPhase = ''
        cp ${pkgs.writeText "rain-overlay.c" rainC} rain-overlay.c

        wayland-scanner client-header \
          < ${pkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
          > xdg-shell-client.h
        wayland-scanner private-code \
          < ${pkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
          > xdg-shell-protocol.c

        wayland-scanner client-header \
          < ${pkgs.wlr-protocols}/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml \
          > wlr-layer-shell-client.h
        wayland-scanner private-code \
          < ${pkgs.wlr-protocols}/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml \
          > wlr-layer-shell-protocol.c

        gcc rain-overlay.c xdg-shell-protocol.c wlr-layer-shell-protocol.c \
          -I. -I${pkgs.stb}/include -O2 -std=gnu11 \
          $(pkg-config --cflags --libs wayland-client wayland-egl egl glesv2) \
          -lm -o rain-overlay
      '';

      installPhase = ''
        mkdir -p $out/bin
        cp rain-overlay $out/bin/rain-overlay
      '';
    };

    # ── Toggle script ──────────────────────────────────────────────────────────
    # rain-toggle [on|off|toggle]
    # rain-toggle wallpaper /path  — hot-swap wallpaper while running (SIGUSR1)
    rainToggle = pkgs.writeShellScriptBin "rain-toggle" ''
      PIDFILE="''${XDG_RUNTIME_DIR:-/tmp}/rain-overlay.pid"
      WALLFILE="''${XDG_RUNTIME_DIR:-/tmp}/rain-overlay.wallpaper"

      _find_wallpaper() {
        [ -f "$WALLFILE" ] && [ -s "$WALLFILE" ] && cat "$WALLFILE" && return
        local walldir
        walldir=$(${pkgs.jq}/bin/jq -r '.paths.wallpaper // empty' \
          "$HOME/.config/skwd-wall/config.json" 2>/dev/null)
        walldir="''${walldir/#\~/$HOME}"
        [ -n "$walldir" ] && [ -d "$walldir" ] && \
          find "$walldir" -maxdepth 1 -type f \
            \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
            -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}'
      }

      _start() {
        local wp; wp=$(_find_wallpaper)
        [ -n "$wp" ] && echo "$wp" > "$WALLFILE"
        ${rainOverlay}/bin/rain-overlay &
        echo $! > "$PIDFILE"
        notify-send -t 2000 -i weather-showers "Rain Effect" "On" 2>/dev/null || true
      }

      _stop() {
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
        notify-send -t 2000 -i weather-clear "Rain Effect" "Off" 2>/dev/null || true
      }

      _running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

      case "''${1:-toggle}" in
        on)        _running || _start ;;
        off)       _running && _stop  ;;
        toggle)    _running && _stop || _start ;;
        wallpaper)
          echo "$2" > "$WALLFILE"
          _running && pkill -USR1 rain-overlay 2>/dev/null || true
          ;;
        *) echo "Usage: rain-toggle [on|off|toggle|wallpaper PATH]" >&2; exit 1 ;;
      esac
    '';

  in {
    home-manager.users.${activeUser} = {
      home.packages = [ rainOverlay rainToggle ];
    };
  };
}
