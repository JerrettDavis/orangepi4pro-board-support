#include <libusb-1.0/libusb.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static volatile sig_atomic_t running = 1;

static void on_sigint(int sig) {
    (void)sig;
    running = 0;
}

static void dump_packet(const unsigned char *buf, int len) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    printf("%ld.%03ld len=%d", ts.tv_sec, ts.tv_nsec / 1000000, len);
    for (int i = 0; i < len; i++) {
        printf(" %02x", buf[i]);
    }
    printf("\n");
    fflush(stdout);
}

int main(void) {
    libusb_context *ctx = NULL;
    libusb_device_handle *dev = NULL;
    int rc;

    signal(SIGINT, on_sigint);
    signal(SIGTERM, on_sigint);

    rc = libusb_init(&ctx);
    if (rc < 0) {
        fprintf(stderr, "libusb_init: %s\n", libusb_error_name(rc));
        return 1;
    }

    dev = libusb_open_device_with_vid_pid(ctx, 0x0484, 0x5750);
    if (!dev) {
        fprintf(stderr, "Could not open 0484:5750\n");
        libusb_exit(ctx);
        return 1;
    }

    if (libusb_kernel_driver_active(dev, 0) == 1) {
        rc = libusb_detach_kernel_driver(dev, 0);
        if (rc < 0) {
            fprintf(stderr, "detach kernel driver: %s\n", libusb_error_name(rc));
        }
    }

    rc = libusb_claim_interface(dev, 0);
    if (rc < 0) {
        fprintf(stderr, "claim interface: %s\n", libusb_error_name(rc));
        libusb_close(dev);
        libusb_exit(ctx);
        return 1;
    }

    fprintf(stderr, "Reading QDtech MPI7003 raw USB reports. Tap the panel; Ctrl-C to stop.\n");
    while (running) {
        unsigned char buf[64] = {0};
        int transferred = 0;
        rc = libusb_interrupt_transfer(dev, 0x82, buf, sizeof(buf), &transferred, 1000);
        if (rc == 0 && transferred > 0) {
            dump_packet(buf, transferred);
        } else if (rc != LIBUSB_ERROR_TIMEOUT && rc != LIBUSB_ERROR_INTERRUPTED) {
            fprintf(stderr, "interrupt read: %s\n", libusb_error_name(rc));
            break;
        }
    }

    libusb_release_interface(dev, 0);
    libusb_attach_kernel_driver(dev, 0);
    libusb_close(dev);
    libusb_exit(ctx);
    return 0;
}
