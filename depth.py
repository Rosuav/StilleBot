import json
import glob

def search(path, data):
	print(len(path), "/".join(path), type(data).__name__)
	# Some things are stored as blobs - don't bother recursing into them.
	if len(path) > 2 and path[1] == "commands": return
	if len(path) > 3 and path[1] == "userprefs": return
	if isinstance(data, list): data = enumerate(data)
	elif isinstance(data, dict): data = data.items()
	else: return
	for key, val in data:
		search(path + (str(key),), val)

for fn in glob.glob("*.json") + glob.glob("channels/*.json"):
	with open(fn, "rb") as f: search((fn,), json.load(f))
