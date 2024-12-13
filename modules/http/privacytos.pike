inherit http_endpoint;

constant markdown = #"# Third party user information

Mustard Mine retains an absolute minimum of your personal information. When you synchronize
your account on another platform such as Twitch, Patreon, Google, or any other provider,
Mustard Mine will record your user ID on that service in order to recognize you when you
return.

## Terms of Service

You are expected to use the Mustard Mine's tools within the limitations of each respective
service's terms and conditions. Using the Mustard Mine to violate another service's TOS may
result in your access to the Mustard Mine being revoked.
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render_template(markdown, ([]));
}
