import urllib.request, json

run_id = '30916887963'
url = f'https://api.github.com/repos/Ahmed-Salah-Ahmed-AbdulHamid/DCO-Project/actions/runs/{run_id}'
req = urllib.request.Request(url)
req.add_header('Accept', 'application/vnd.github.v3+json')
run = json.loads(urllib.request.urlopen(req).read())
print(f"Run #{run['run_number']}")
print(f"Head SHA: {run['head_sha']}")
print(f"Message: {run['head_commit']['message']}")
print(f"Attempt: {run['run_attempt']}")
