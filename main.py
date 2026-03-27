from fastapi import FastAPI, UploadFile, File, HTTPException, Query
from fastapi.responses import FileResponse
from typing import List
import torch
import torch.nn.functional as F
from torchvision import transforms
import timm
from PIL import Image
import io
import imagehash
import uvicorn
import os
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# ---------------------------------------------------------
# CORS SETUP (For Flutter Connectivity)
# ---------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------
# GLOBAL SESSION MEMORY (Optimized)
# ---------------------------------------------------------
processed_images = []

# ---------------------------------------------------------
# 1. MODEL SETUP (Vision Transformer - ViT)
# ---------------------------------------------------------
# ViT is state-of-the-art for image feature extraction
model_name = 'vit_tiny_patch16_224'
try:
    model = timm.create_model(model_name, pretrained=True, num_classes=0)
    model.eval()
    print(f"✅ AI Model ({model_name}) Loaded Successfully!")
except Exception as e:
    print(f"❌ Model Loading Failed: {e}")

# Preprocessing for ViT (Standard ImageNet Normalization)
preprocess = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
])

# ---------------------------------------------------------
# 2. CORE AI LOGIC
# ---------------------------------------------------------

def get_vit_embedding(image_pil):
    """Generates normalized feature embedding using Vision Transformer."""
    img_tensor = preprocess(image_pil).unsqueeze(0)
    with torch.no_grad():
        features = model(img_tensor)
        # Normalize for better Cosine Similarity
        features = F.normalize(features, p=2, dim=1)
    return features

# ---------------------------------------------------------
# 3. API ENDPOINTS
# ---------------------------------------------------------

@app.get("/")
def health_check():
    return {
        "status": "AI Deduplication Engine Online", 
        "engine": "Vision Transformer (ViT)",
        "memory_count": len(processed_images)
    }

@app.get("/reset_session")
def reset_session():
    global processed_images
    processed_images = []
    print("\n🧹 Session Cleared: Ready for new Scan.")
    return {"status": "success", "message": "Backend memory reset completed"}

@app.post("/compare")
async def compare_batch(files: List[UploadFile] = File(...)):
    global processed_images
    batch_results = []

    print(f"\n📥 Analyzing Batch: {len(files)} images...")

    for file in files:
        try:
            content = await file.read()
            img_pil = Image.open(io.BytesIO(content)).convert('RGB')
            
            # 1. Extract Features (AI & Perceptual)
            feat = get_vit_embedding(img_pil)
            phash = imagehash.phash(img_pil)
            
            is_match = False
            match_data = None

            # 2. Compare against already processed images in current session
            for old_img in processed_images:
                # Cosine Similarity (0 to 1) -> 1 means identical
                cos_sim = F.cosine_similarity(feat, old_img["features"]).item()
                similarity_percent = round(cos_sim * 100, 2)
                
                # Hamming distance for perceptual hash
                hash_diff = phash - old_img["phash"]

                # --- CATEGORIZATION LOGIC ---
                
                # A. EXACT DUPLICATE (Pixel-level or Hash match)
                if hash_diff == 0 or similarity_percent > 99.5:
                    is_match = True
                    match_data = {
                        "pair": [file.filename, old_img["filename"]],
                        "similarity": 100,
                        "status": "Exact Duplicate"
                    }
                    print(f"  🚨 EXACT: {file.filename}")
                    break

                # B. NEAR DUPLICATE (Brightness, Crop, Noise, Rotated)
                # MSc Thesis Recommendation: Threshold between 78% to 95%
                elif similarity_percent > 80.0:
                    is_match = True
                    match_data = {
                        "pair": [file.filename, old_img["filename"]],
                        "similarity": similarity_percent,
                        "status": "Near-Duplicate"
                    }
                    print(f"  ⚠️ NEAR: {file.filename} ({similarity_percent}%)")
                    break

            # 3. Save to Session Memory (to compare next images against this one)
            processed_images.append({
                "filename": file.filename,
                "features": feat,
                "phash": phash
            })

            if is_match:
                batch_results.append(match_data)

        except Exception as e:
            print(f"  ❌ Failed to process {file.filename}: {e}")
            continue

    return {"duplicates": batch_results}

# Selective "Keep" Verification
@app.get("/verify-path/")
async def verify_path(path: str = Query(...)):
    if os.path.exists(path):
        return {"status": "exists"}
    raise HTTPException(status_code=404, detail="File not found on Host")

if __name__ == "__main__":
    # host="0.0.0.0" is mandatory for Mobile-to-Laptop connection
    uvicorn.run(app, host="0.0.0.0", port=8000)