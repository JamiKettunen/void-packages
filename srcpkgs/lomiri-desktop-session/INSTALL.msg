To start a Lomiri desktop session you must:

	ln -s /etc/sv/dbus /var/service            # enable & start the D-Bus system service
	NO_X11=1 dbus-run-session lomiri-session   # start Lomiri along with a D-Bus session (without X11 support)

