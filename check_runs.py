import urllib.request, json

url = 'https://api.github.com/repos/Ahmed-Salah-Ahmed-AbdulHamid/DCO-Project/actions/runs?per_page=5'
req = urllib.request.Request(url)
req.add_header('Accept', 'application/vnd.github.v3+json')
runs = json.loads(urllib.request.urlopen(req).read())['workflow_runs']

for r in runs:
    msg = r['head_commit']['message'][:55].strip()
    c = r['conclusion'] or r['status']
    print(f"#{r['run_number']} | {c:10} | {msg}")
    print(f"   CLICK: {r['html_url']}")
    print()
