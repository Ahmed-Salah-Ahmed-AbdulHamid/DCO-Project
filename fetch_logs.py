import urllib.request, json, zipfile, io, glob

runs_url = 'https://api.github.com/repos/Ahmed-Salah-Ahmed-AbdulHamid/DCO-Project/actions/runs'
req = urllib.request.Request(runs_url)
runs = json.loads(urllib.request.urlopen(req).read())['workflow_runs']
latest_run = runs[0]

logs_url = latest_run['logs_url']
print(f"Downloading logs from: {logs_url}")

req = urllib.request.Request(logs_url)
try:
    with urllib.request.urlopen(req) as response:
        with zipfile.ZipFile(io.BytesIO(response.read())) as z:
            z.extractall('logs_temp')
    print("Extracted logs to logs_temp/")
    
    # Find the log for "CI - Test" or similar
    for file in glob.glob('logs_temp/**/*.txt', recursive=True):
        if 'Test' in file or 'test' in file:
            with open(file, 'r', encoding='utf-8') as f:
                content = f.read()
                if 'FAILED' in content or 'Error' in content:
                    print(f"\n--- Found error in {file} ---")
                    lines = content.split('\n')
                    for line in lines[-50:]:
                        print(line)
except Exception as e:
    print(f"Error fetching logs: {e}")
