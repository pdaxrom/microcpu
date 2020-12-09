#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <stdarg.h>
#include <usb.h>

#define USB_VENDOR 0x0403
#define USB_PRODUCT 0x6010

struct usb_bus *USB_init()
{
    usb_init();
    usb_find_busses();
    usb_find_devices();
    return (usb_get_busses());
}

struct usb_device *USB_find(struct usb_bus *busses, struct usb_device *dev)
{
    struct usb_bus *bus;
    for (bus = busses; bus; bus = bus->next) {
        for (dev = bus->devices; dev; dev = dev->next) {
            if ((dev->descriptor.idVendor == USB_VENDOR) && (dev->descriptor.idProduct == USB_PRODUCT)) {
                return (dev);
            }
        }
    }
    return (NULL);
}

int main(int argc, char *argv[])
{
    struct usb_bus *bus;
    struct usb_device *dev;

    printf("Find device...\n");

    bus = USB_init();
    dev = USB_find(bus, dev);

    if (dev) {
        struct usb_dev_handle *udev = NULL;

        printf("Open device...\n");

        udev = usb_open(dev);
        if ((udev = usb_open(dev))) {
            printf("Detach interface...\n");
            if (usb_detach_kernel_driver_np(udev, 0) < 0) {
                fprintf(stderr, "usb_set_configuration Error.\n");
                fprintf(stderr, "usb_detach_kernel_driver_np Error.(%s)\n", usb_strerror());
            }

            if (usb_close(udev) < 0) {
                fprintf(stderr, "usb_close Error.(%s)\n", usb_strerror());
            }
        } else {
            fprintf(stderr, "usb_open Error.(%s)\n", usb_strerror());
        }
    } else {
        fprintf(stderr, "device not found!\n");
    }

    return 0;
}
