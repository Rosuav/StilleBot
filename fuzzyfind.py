import json
import os.path
import sys
from fuzzywuzzy import process, fuzz # ImportError? pip install 'fuzzywuzzy[speedup]'

with open("all_follows.txt") as f:
	followers = [l.strip() for l in f if l.strip()]

def shortest_token_set_ratio(query, choice):
	"""Like fuzz.token_set_ratio, but breaks ties by choosing the shortest"""
	return fuzz.token_set_ratio(query, choice) * 1000 + 1000 - len(choice)
def show_matches(target):
	# For numeric targets, reverse the lookup
	try:
		target = int(target)
		# TODO: Cache the reverse lookup in its own dict?
		for name, id in appids.items():
			if id == target:
				print(name)
				break
		return
	except ValueError:
		pass
	for name, score in process.extract(target, followers, limit=10, scorer=shortest_token_set_ratio):
		print("\t[%3d%%] %s" % (score//1000, name))

if len(sys.argv) > 1:
	for arg in sys.argv[1:]:
		print(arg)
		show_matches(arg)
else:
	while True:
		name = input("Enter a name: ")
		if not name: break
		show_matches(name)
