/* Key request client

Connects to keyfob.py from sugar-mill to access certs and private keys

TODO: String.secure the keys after loading them
TODO: Switch to an actual secret instead of Hello World (save it into instance-config)
TODO: Failure modes?
*/

string totp(string secret) {
	object hmac = Crypto.SHA1.HMAC(MIME.decode_base32(secret));
	int input = time() / 30;
	string hash = hmac(sprintf("%8c", input));
	int offset = hash[-1] & 15;
	sscanf(hash[offset..offset+3], "%4c", int code);
	code &= 0x7fffffff; //It's a 31-bit code, mask off the high bit
	return ("00000000" + (string)code)[<7..]; //Assumes eight-digit codes
}

string authcode() {
	mapping instance_config = Standards.JSON.decode_utf8(Stdio.read_file("instance-config.json"));
	return totp(instance_config->sugar || "JBSWY3DPEHPK3PXP");
}

string buf = "";
array|zero file_receive = 0;
System.Timer tm = System.Timer();
void readable(object sock, string data) {
	buf += data;
	while (sscanf(buf, "%s\n%s", string line, buf) == 2) {
		if (file_receive) {
			if (line == ".") {
				//File complete!
				write("Have file %O\n%O\n%fs\n", file_receive[0], String.string2hex(Crypto.SHA1.hash(file_receive[1])), tm->peek());
				file_receive = 0;
				continue;
			}
			file_receive[1] += line + "\n";
			continue;
		}
		[string cmd, array args] = Array.shift(line / " ");
		switch (cmd) {
			case "hello": write("Attempting auth...\n"); sock->write("auth %s\n", authcode()); break;
			case "login": write("Login OK\n"); sock->write("fetch db.rosuav.com\n"); break;
			case "certificate": file_receive = ({args[0], ""}); break;
			default: break;
		}
	}
}
//Buffer full should never be an issue with the tiny amounts we send
void writable(object sock) { }
void closed(object sock) {exit(0);}

__async__ void get_cert() {
	write("I am PID %O\n", getpid());
	object sock = Stdio.File();
	sock->open_socket();
	sock->set_nonblocking(readable, writable, closed);
	if (!sock->connect_unix("/var/run/certmgr")) exit(0, "Server not running\n");
}

int main() {
	get_cert();
	return -1;
}
