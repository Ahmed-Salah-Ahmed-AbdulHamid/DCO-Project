import urllib.request
import os
import concurrent.futures

output_dir = "test_images"
os.makedirs(output_dir, exist_ok=True)

print(f"Downloading 100 images to {os.path.abspath(output_dir)}...")

def download_image(i):
    url = f"https://picsum.photos/seed/nature{i}/800/600"
    path = os.path.join(output_dir, f"nature_{i:03d}.jpg")
    try:
        urllib.request.urlretrieve(url, path)
    except Exception as e:
        print(f"Failed {path}: {e}")

with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
    executor.map(download_image, range(1, 101))

print("Successfully downloaded 100 images!")
