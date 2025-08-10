Change 10/08/2025
🆕 What's New

This Docker container is now fully automated — no manual setup required!
✅ Automatic Setup

    On first run, the container automatically downloads docker-entrypoint.sh.

    It then checks for the presence of fan_control.sh in /usr/local/data/:

        If the script already exists, it is left untouched.

        If the script is missing, it is automatically downloaded from GitHub.

🧪 Not Yet in Community Applications?

If the container hasn’t been published to the Community Applications repository yet, you can still deploy it manually:

    Place the Docker template XML file in:

    /boot/config/plugins/dockerMan/templates-user/

    Deploy the container from the Unraid Docker tab using the template.

This setup ensures fan_control.sh is always available without requiring any manual intervention — making installation and maintenance simple and reliable.


Change 09/08/2025 Still learning, I have moved the files to be copied to github so the build is getting the correct files. I am still working out on how to get the default files to the appdata. Since this isn't available on unraid appstore it is hard to work out the bug.

Change 08/08/2025 Fan Control Docker for NZXT RGB & Fan Controller (AC-CRFR0-B1-6)

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
