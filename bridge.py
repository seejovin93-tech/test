import subprocess, json, sys, time

# Configuration injected from Shell
REPO = "prufwerk"
REGION = "ap-east-2"
TARGET_DIGEST = "sha256:edac4e34820f1a7a1ede4ab1269f509d8284db4febd5eb6542ae9cc8e5e4cac9"
NONCE = "s3-8-run-1763497522" 
LEGACY_TAG = TARGET_DIGEST.replace("sha256:", "sha256-") + ".sig"

def run(cmd):
    # Helper to run shell commands quietly
    return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode('utf-8').strip()

print(f"    👀  Hunting for signature linked to: {TARGET_DIGEST[:12]}...")

found = False
# Loop 12 times (approx 60 seconds)
for i in range(1, 13):
    sys.stdout.write(f"        Attempt {i}/12...")
    sys.stdout.flush()
    
    try:
        # 1. List all images in the repo
        out = run(f"aws ecr list-images --repository-name {REPO} --region {REGION} --output json")
        images = json.loads(out).get('imageIds', [])
        
        for img in images:
            d = img.get('imageDigest')
            # Skip the image itself, look for other blobs (signatures)
            if not d or d == TARGET_DIGEST: continue 
            
            # 2. Inspect the Manifest of this blob
            manifest = run(f"aws ecr batch-get-image --repository-name {REPO} --region {REGION} --image-ids imageDigest={d} --query 'images[0].imageManifest' --output text")
            
            # 3. Logic: Is this OUR signature?
            # If we have a NONCE, it MUST match. If not, any cosign signature works.
            is_match = False
            if NONCE and NONCE in manifest:
                is_match = True
            elif not NONCE and "dev.cosignproject.cosign/signature" in manifest:
                is_match = True
                
            if is_match:
                print(f" FOUND!")
                print(f"        🏷️   Applying Legacy Tag: {LEGACY_TAG}")
                
                # 4. Create the Tag (The Fix)
                with open("sig.json", "w") as f: f.write(manifest)
                
                # Safety: Remove tag if it already exists (cleanup)
                try: run(f"aws ecr batch-delete-image --repository-name {REPO} --region {REGION} --image-ids imageTag={LEGACY_TAG}")
                except: pass
                
                # Push the Tag
                run(f"aws ecr put-image --repository-name {REPO} --region {REGION} --image-tag {LEGACY_TAG} --image-manifest file://sig.json")
                
                found = True
                break
    except Exception as e:
        # Ignore errors during polling (common in eventual consistency)
        pass
    
    if found: break
    print(" waiting...")
    time.sleep(5)

if not found:
    print("\n    ❌ ERROR: Signature not found after 60s. AWS Latency or Upload Failure.")
    sys.exit(1)

print("    ✅ Bridge Crossed: Signature is visible and tagged.")
