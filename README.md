Fan Control Docker for NZXT RGB & Fan Controller (AC-CRFR0-B1-6)

Welcome! This Docker container was created to help control the fans connected to the NZXT RGB & Fan Controller (model AC-CRFR0-B1-6). The goal is to reduce noise when your array is spun down—perfect if you mostly use your cache for media and want quieter operation.
About

This project was inspired by psteward's work on Unraid forums. It focuses specifically on managing fan speeds via liquidctl inside a Docker container, running in your environment.

The NZXT controller supports up to 3 fans plus LED control; this container currently focuses on fan management only.
Features

    Control up to 3 fans connected to the NZXT RGB & Fan Controller.

    Runs as a lightweight Debian-based Docker container.

    Uses liquidctl for communicating with the hardware.

    Scheduled fan speed adjustments via cron jobs.

    Designed for quieter operation when disk arrays spin down.

Usage

    Build the Docker image:

docker build -t yourusername/minimal-liquidctl .

Run the container, mounting any needed volumes or devices (e.g., USB access):

    docker run --rm --privileged -v /dev/bus/usb:/dev/bus/usb yourusername/minimal-liquidctl

    Configure environment variables or scripts as needed to suit your fan control preferences.

Notes

    This container and setup have been tested for personal use; your mileage may vary depending on hardware and environment.

    Make sure USB devices are accessible inside the container (--privileged and device mounts).

    Adjust fan control scripts (fan_control.sh) to match your fan speed profiles.

Feedback & Contributions

If you find bugs, have suggestions, or improvements, feel free to open an issue or submit a pull request. Your feedback is appreciated!
License

This project is provided as-is without warranty. Use at your own risk.
