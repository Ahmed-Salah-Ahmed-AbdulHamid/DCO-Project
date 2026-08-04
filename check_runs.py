import urllib.request, json
url = 'https://api.github.com/repos/Ahmed-Salah-Ahmed-AbdulHamid/DCO-Project/actions/runs'
req = urllib.request.Request(url)
runs = json.loads(urllib.request.urlopen(req).read())['workflow_runs']
for r in runs[:5]:
    print(f"ID: {r['id']} | Status: {r['status']} | Conclusion: {r['conclusion']} | Msg: {r['head_commit']['message'][:40].strip()}")
