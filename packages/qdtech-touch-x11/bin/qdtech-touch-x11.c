#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <libusb-1.0/libusb.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define VID 0x0484
#define PID 0x5750
#define IFACE 0
#define EP_IN 0x82

static volatile sig_atomic_t running = 1;

struct calib {
    int min_x;
    int max_x;
    int min_y;
    int max_y;
};

static void on_signal(int sig) {
    (void)sig;
    running = 0;
}

static int clamp_int(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

static int map_axis(int raw, int min_raw, int max_raw, int out_max) {
    if (max_raw == min_raw) return 0;
    double t = (double)(raw - min_raw) / (double)(max_raw - min_raw);
    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;
    return (int)(t * (double)(out_max - 1) + 0.5);
}

static void load_calib(struct calib *c) {
    const char *path = getenv("QDTECH_TOUCH_CALIB");
    if (!path) path = "/etc/qdtech-touch-x11.conf";

    c->min_x = 0;
    c->max_x = 1024;
    c->min_y = 0;
    c->max_y = 600;

    FILE *f = fopen(path, "r");
    if (!f) return;

    char key[64];
    int value;
    while (fscanf(f, " %63[^=]=%d", key, &value) == 2) {
        if (strcmp(key, "MIN_X") == 0) c->min_x = value;
        else if (strcmp(key, "MAX_X") == 0) c->max_x = value;
        else if (strcmp(key, "MIN_Y") == 0) c->min_y = value;
        else if (strcmp(key, "MAX_Y") == 0) c->max_y = value;
        int ch;
        while ((ch = fgetc(f)) != '\n' && ch != EOF) {}
    }
    fclose(f);
}

static void disable_broken_xinput(void) {
    const char *display = getenv("DISPLAY");
    const char *xauth = getenv("XAUTHORITY");
    if (!display || !xauth) return;
    pid_t pid = fork();
    if (pid == 0) {
        execlp("xinput", "xinput", "disable", "QDtech MPI7003 Touchscreen", (char *)NULL);
        _exit(127);
    }
}

int main(void) {
    libusb_context *ctx = NULL;
    libusb_device_handle *usb = NULL;
    Display *dpy = NULL;
    struct calib calib;
    int rc;
    int pressed = 0;
    int last_x = -1;
    int last_y = -1;
    int verbose = getenv("QDTECH_TOUCH_VERBOSE") != NULL;

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGHUP, on_signal);

    load_calib(&calib);

    dpy = XOpenDisplay(NULL);
    if (!dpy) {
        fprintf(stderr, "Could not open X display. DISPLAY=%s XAUTHORITY=%s\n",
                getenv("DISPLAY") ? getenv("DISPLAY") : "",
                getenv("XAUTHORITY") ? getenv("XAUTHORITY") : "");
        return 1;
    }

    int event_base, error_base, major, minor;
    major = 2;
    minor = 2;
    if (!XTestQueryExtension(dpy, &event_base, &error_base, &major, &minor)) {
        fprintf(stderr, "XTEST extension is not available\n");
        XCloseDisplay(dpy);
        return 1;
    }

    int screen = DefaultScreen(dpy);
    int screen_w = DisplayWidth(dpy, screen);
    int screen_h = DisplayHeight(dpy, screen);

    rc = libusb_init(&ctx);
    if (rc < 0) {
        fprintf(stderr, "libusb_init: %s\n", libusb_error_name(rc));
        XCloseDisplay(dpy);
        return 1;
    }

    usb = libusb_open_device_with_vid_pid(ctx, VID, PID);
    if (!usb) {
        fprintf(stderr, "Could not open USB device %04x:%04x\n", VID, PID);
        libusb_exit(ctx);
        XCloseDisplay(dpy);
        return 1;
    }

    disable_broken_xinput();

    if (libusb_kernel_driver_active(usb, IFACE) == 1) {
        rc = libusb_detach_kernel_driver(usb, IFACE);
        if (rc < 0) {
            fprintf(stderr, "detach kernel driver: %s\n", libusb_error_name(rc));
        }
    }

    rc = libusb_claim_interface(usb, IFACE);
    if (rc < 0) {
        fprintf(stderr, "claim interface: %s\n", libusb_error_name(rc));
        libusb_close(usb);
        libusb_exit(ctx);
        XCloseDisplay(dpy);
        return 1;
    }

    fprintf(stderr,
            "QDtech X11 bridge running: screen=%dx%d calib=%d,%d,%d,%d\n",
            screen_w, screen_h, calib.min_x, calib.max_x, calib.min_y, calib.max_y);

    while (running) {
        unsigned char buf[64] = {0};
        int transferred = 0;
        rc = libusb_interrupt_transfer(usb, EP_IN, buf, sizeof(buf), &transferred, 1000);
        if (rc == LIBUSB_ERROR_TIMEOUT || rc == LIBUSB_ERROR_INTERRUPTED) {
            continue;
        }
        if (rc < 0) {
            fprintf(stderr, "interrupt read: %s\n", libusb_error_name(rc));
            break;
        }
        if (transferred < 7 || buf[0] != 0x01) {
            continue;
        }

        int touching = buf[1] & 0x01;
        int raw_x = (int)buf[3] | ((int)buf[4] << 8);
        int raw_y = (int)buf[5] | ((int)buf[6] << 8);
        int x = map_axis(raw_x, calib.min_x, calib.max_x, screen_w);
        int y = map_axis(raw_y, calib.min_y, calib.max_y, screen_h);
        x = clamp_int(x, 0, screen_w - 1);
        y = clamp_int(y, 0, screen_h - 1);

        if (touching) {
            if (verbose && (x != last_x || y != last_y || !pressed)) {
                fprintf(stderr, "touch raw=%d,%d screen=%d,%d pressed=%d\n",
                        raw_x, raw_y, x, y, pressed);
            }
            if (x != last_x || y != last_y) {
                XTestFakeMotionEvent(dpy, screen, x, y, CurrentTime);
                last_x = x;
                last_y = y;
            }
            if (!pressed) {
                XTestFakeButtonEvent(dpy, 1, True, CurrentTime);
                pressed = 1;
            }
            XFlush(dpy);
        } else if (pressed) {
            if (verbose) {
                fprintf(stderr, "release raw=%d,%d screen=%d,%d\n", raw_x, raw_y, x, y);
            }
            XTestFakeButtonEvent(dpy, 1, False, CurrentTime);
            XFlush(dpy);
            pressed = 0;
        }
    }

    if (pressed) {
        XTestFakeButtonEvent(dpy, 1, False, CurrentTime);
        XFlush(dpy);
    }
    libusb_release_interface(usb, IFACE);
    libusb_attach_kernel_driver(usb, IFACE);
    libusb_close(usb);
    libusb_exit(ctx);
    XCloseDisplay(dpy);
    return 0;
}
