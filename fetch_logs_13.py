import urllib.request, json, zipfile, io, glob

run_id = '30917713532'
url = f'https://api.github.com/repos/Ahmed-Salah-Ahmed-AbdulHamid/DCO-Project/actions/runs/{run_id}/jobs'
req = urllib.request.Request(url)
req.add_header('Accept', 'application/vnd.github.v3+json')
jobs = json.loads(urllib.request.urlopen(req).read())['jobs']

for j in jobs:
    if j['name'] == 'CD — Build & Push to ECR':
        job_id = j['id']
        print(f"Fetching logs for job {job_id}...")
        try:
            log_url = f'https://api.github.com/repos/Ahmed-Salah-Ahmed-AbdulHamid/DCO-Project/actions/jobs/{job_id}/logs'
            req2 = urllib.request.Request(log_url)
            req2.add_header('Accept', 'application/vnd.github.v3+json')
            log_content = urllib.request.urlopen(req2).read().decode('utf-8')
            print("--- LOG CONTENT ---")
            lines = log_content.split('\n')
            for line in lines[-100:]:
                print(line)
        except Exception as e:
            print(f"Error fetching logs: {e}")
