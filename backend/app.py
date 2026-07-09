from fastapi import FastAPI
from inference import load_assets
from database import init_db
from routes import router

# Initialize FastAPI app
app = FastAPI(title="EdgeSense HAR Server")

@app.on_event("startup")
def startup_event():
    load_assets()
    init_db()

# Include the router containing all endpoints
app.include_router(router)