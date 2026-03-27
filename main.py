from fastapi import FastAPI, UploadFile, File, HTTPException, Query
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
# GLOBAL SESSION MEMORY
# ---------------------------------------------------------
processed_images = []

# ---------------------------------------------------------
# MODEL SETUP (ViT)
# ---------------------------------------------------------
model_name = 'vit_tiny_patch16_224'

try:
    model = timm.create_model(model_name, pretrained=True, num_classes=0)
    model.eval()
    print(f"✅ AI Model ({model_name}) Loaded Successfully!")
except Exception as e:
    print(f"❌ Model Loading Failed: {e}")

preprocess = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406],
                         std=[0.229, 0.224, 0.225]),
])

# ---------------------------------------------------------
# CORE FUNCTION
# ---------------------------------------------------------
def get_vit_embedding(image_pil):
    img_tensor = preprocess(image_pil).unsqueeze(0)
    with torch.no_grad():
        features = model(img_tensor)
        features = F.normalize(features, p=2, dim=1)
    return features

# ---------------------------------------------------------
# API ENDPOINTS
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
    print("\n🧹 Session Cleared")
    return {"status": "success"}

@app.post("/compare")
async def compare_batch(files: List[UploadFile] = File(...)):
    global processed_images
    batch_results = []

    print(f"\n📥 Processing {len(files)} images...")

    for file in files:
        try:
            content = await file.read()
            img_pil = Image.open(io.BytesIO(content)).convert('RGB')

            feat = get_vit_embedding(img_pil)
            phash = imagehash.phash(img_pil)

            is_match = False
            match_data = None

            for old_img in processed_images:
                cos_sim = F.cosine_similarity(feat, old_img["features"]).item()
                similarity_percent = round(cos_sim * 100, 2)
                hash_diff = phash - old_img["phash"]

                if hash_diff == 0 or similarity_percent > 99.5:
                    is_match = True
                    match_data = {
                        "pair": [file.filename, old_img["filename"]],
                        "similarity": 100,
                        "status": "Exact Duplicate"
                    }
                    break

                elif similarity_percent > 80.0:
                    is_match = True
                    match_data = {
                        "pair": [file.filename, old_img["filename"]],
                        "similarity": similarity_percent,
                        "status": "Near-Duplicate"
                    }
                    break

            processed_images.append({
                "filename": file.filename,
                "features": feat,
                "phash": phash
            })

            if is_match:
                batch_results.append(match_data)

        except Exception as e:
            print(f"❌ Error processing {file.filename}: {e}")
            continue

    return {"duplicates": batch_results}

@app.get("/verify-path/")
async def verify_path(path: str = Query(...)):
    if os.path.exists(path):
        return {"status": "exists"}
    raise HTTPException(status_code=404, detail="File not found")

# ---------------------------------------------------------
# MAIN (FIXED FOR DEPLOY)
# ---------------------------------------------------------
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 10000))
    uvicorn.run(app, host="0.0.0.0", port=port)
