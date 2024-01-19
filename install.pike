//Create a systemd service file for the bot
//Uses the invocation pike binary for the bot too, so run this with
//whichever Pike is appropriate.
//Note: This does NOT enable the service. If you want it to autostart,
//do this manually.

int main() {
	string user = getenv("SUDO_USER");
	if (!user) exit(1, "Run this with sudo to ensure that the correct user invokes the bot.\n");
	string binary = readlink("/proc/self/exe");
	Stdio.write_file("/etc/systemd/system/stillebot.service", sprintf(#"[Service]
User=%s
WorkingDirectory=%s
ExecStart=%s stillebot --headless
ExecReload=kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
", user, getcwd(), binary));
}
