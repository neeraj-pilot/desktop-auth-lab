#include "my_application.h"

#include <dlfcn.h>
#include <flutter_linux/flutter_linux.h>
#include <sys/utsname.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* diagnostics_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void map_set_value(FlValue* map, const gchar* key, FlValue* value) {
  fl_value_set_take(map, fl_value_new_string(key), value);
}

static void map_set_string(FlValue* map, const gchar* key, const gchar* value) {
  map_set_value(map, key, fl_value_new_string(value != nullptr ? value : ""));
}

static void map_set_bool(FlValue* map, const gchar* key, gboolean value) {
  map_set_value(map, key, fl_value_new_bool(value));
}

static void add_file_probe(FlValue* map, const gchar* path, const gchar* label) {
  g_autoptr(FlValue) probe = fl_value_new_map();
  map_set_string(probe, "label", label);
  map_set_bool(probe, "exists", g_file_test(path, G_FILE_TEST_EXISTS));
  map_set_bool(probe, "regularFile", g_file_test(path, G_FILE_TEST_IS_REGULAR));
  fl_value_set_take(map, fl_value_new_string(path), fl_value_ref(probe));
}

static void add_command_probe(FlValue* map, const gchar* command) {
  g_autofree gchar* path = g_find_program_in_path(command);
  g_autoptr(FlValue) probe = fl_value_new_map();
  map_set_bool(probe, "available", path != nullptr);
  map_set_string(probe, "path", path);
  fl_value_set_take(map, fl_value_new_string(command), fl_value_ref(probe));
}

static void add_library_probe(FlValue* map, const gchar* library) {
  void* handle = dlopen(library, RTLD_LAZY | RTLD_LOCAL);
  g_autoptr(FlValue) probe = fl_value_new_map();
  map_set_bool(probe, "available", handle != nullptr);
  if (handle != nullptr) {
    dlclose(handle);
  }
  fl_value_set_take(map, fl_value_new_string(library), fl_value_ref(probe));
}

static FlMethodResponse* collect_diagnostics_response() {
  g_autoptr(FlValue) result = fl_value_new_map();
  map_set_bool(result, "available", TRUE);
  map_set_string(result, "user", g_get_user_name());
  map_set_string(result, "home", g_get_home_dir());
  map_set_string(result, "pamServiceDefault", "login");
  map_set_string(result, "pamServiceOverride",
                 g_getenv("FLUTTER_LOCAL_AUTHENTICATION_PAM_SERVICE"));

  struct utsname uts;
  if (uname(&uts) == 0) {
    g_autoptr(FlValue) kernel = fl_value_new_map();
    map_set_string(kernel, "sysname", uts.sysname);
    map_set_string(kernel, "release", uts.release);
    map_set_string(kernel, "version", uts.version);
    map_set_string(kernel, "machine", uts.machine);
    fl_value_set_take(result, fl_value_new_string("kernel"), fl_value_ref(kernel));
  }

  g_autoptr(FlValue) files = fl_value_new_map();
  add_file_probe(files, "/etc/pam.d/login", "default PAM service");
  add_file_probe(files, "/etc/pam.d/sudo", "password PAM service");
  add_file_probe(files, "/etc/pam.d/polkit-1", "desktop policy auth service");
  add_file_probe(files, "/run/dbus/system_bus_socket", "system D-Bus socket");
  fl_value_set_take(result, fl_value_new_string("files"), fl_value_ref(files));

  g_autoptr(FlValue) commands = fl_value_new_map();
  add_command_probe(commands, "fprintd-list");
  add_command_probe(commands, "fprintd-verify");
  add_command_probe(commands, "loginctl");
  add_command_probe(commands, "systemctl");
  add_command_probe(commands, "dbus-send");
  fl_value_set_take(result, fl_value_new_string("commands"), fl_value_ref(commands));

  g_autoptr(FlValue) libraries = fl_value_new_map();
  add_library_probe(libraries, "libpam.so.0");
  add_library_probe(libraries, "libfprint-2.so.2");
  add_library_probe(libraries, "libsecret-1.so.0");
  fl_value_set_take(result, fl_value_new_string("libraries"), fl_value_ref(libraries));

  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void diagnostics_method_call_cb(FlMethodChannel* channel,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  (void)channel;
  (void)user_data;
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "collectDiagnostics") == 0) {
    response = collect_diagnostics_response();
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void create_diagnostics_channel(MyApplication* self, FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->diagnostics_channel = fl_method_channel_new(
      messenger, "desktop_auth_lab/diagnostics", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->diagnostics_channel, diagnostics_method_call_cb, self, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "desktop_auth_lab");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "desktop_auth_lab");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  create_diagnostics_channel(self, view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->diagnostics_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
