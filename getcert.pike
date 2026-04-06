string twofa(string secret) {
	object hmac = Crypto.SHA1.HMAC(MIME.decode_base32(secret));
	int input = time() / 30;
	string hash = hmac(sprintf("%8c", input));
	int offset = hash[-1] & 15;
	sscanf(hash[offset..offset+3], "%4c", int code);
	code &= 0x7fffffff; //It's a 31-bit code, mask off the high bit
	return ("00000000" + (string)code)[<7..]; //Assumes eight-digit codes
}

string buf = "";
void readable(object sock, string data) {
	buf += data;
	while (sscanf(buf, "%s\n%s", string line, buf) == 2) {
		[string cmd, array args] = Array.shift(line / " ");
		switch (cmd) {
			case "hello": write("Attempting auth...\n"); sock->write("auth %s\n", twofa("JBSWY3DPEHPK3PXP")); break;
			case "login": write("Login OK\n"); break;
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
	if (!sock->connect_unix("/tmp/certmgr")) exit(0, "Server not running\n");
}

int main() {
	get_cert();
	return -1;
}
