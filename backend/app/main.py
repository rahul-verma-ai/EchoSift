# backend/app/main.py
import os
import uuid
import logging
from datetime import datetime
from fastapi import FastAPI, UploadFile, File, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from redis.asyncio import Redis, ConnectionPool

from .core.config import get_settings
from .services.ai_service import transcribe_audio, generate_emotional_response

settings = get_settings()

# SAFE DEBUG PRINT
raw_key = os.getenv("OPENAI_API_KEY")
print(f"DEBUG: Raw environment check for Key: {raw_key[:7] if raw_key else 'None Found'}", flush=True)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("echosift")

app = FastAPI(title=settings.app_name)

# ---------- Redis Connection Logic ----------
# If REDIS_URL is present (Cloud), use from_url. Otherwise, use pool (Local).
if settings.redis_url:
    logger.info("Connecting to Redis via REDIS_URL")
    redis = Redis.from_url(settings.redis_url, decode_responses=True)
else:
    logger.info(f"Connecting to Redis via host: {settings.redis_host}")
    redis_pool = ConnectionPool(
        host=settings.redis_host,
        port=settings.redis_port,
        db=settings.redis_db,
        decode_responses=True,
    )
    redis = Redis(connection_pool=redis_pool)

# ---------- Middleware ----------
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_methods=settings.cors_allow_methods,
    allow_headers=settings.cors_allow_headers,
)

@app.middleware("http")
async def request_logger(request: Request, call_next):
    start = datetime.utcnow()
    response = await call_next(request)
    duration = (datetime.utcnow() - start).total_seconds()
    logger.info(
        "%s %s %s %.3fs",
        request.method,
        request.url.path,
        response.status_code,
        duration,
    )
    return response

# ---------- Error Handling ----------
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled exception")
    return JSONResponse(
        status_code=500,
        content={"error": "internal_server_error"},
    )

# ---------- Health ----------
@app.get("/health")
async def health_check():
    try:
        await redis.ping()
        return {"status": "ok", "redis": "connected"}
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=503, detail="redis_unavailable")

# ---------- Core API ----------
@app.post("/session/{session_id}/audio")
async def process_audio(
    session_id: str,
    file: UploadFile = File(...),
):
    if not file.content_type.startswith("audio/"):
        raise HTTPException(status_code=400, detail="invalid_audio_type")

    audio_bytes = await file.read()
    
    # Transcribe audio using OpenAI Whisper
    transcript = await transcribe_audio(audio_bytes, file.filename)

    redis_key = f"session:{session_id}"

    # THE INSURANCE POLICY
    existing_type = await redis.type(redis_key)
    if existing_type != "list" and existing_type != "none":
        await redis.delete(redis_key)

    # Rolling window logic using Redis
    async with redis.pipeline(transaction=True) as pipe:
        pipe.rpush(redis_key, transcript)
        pipe.ltrim(redis_key, -20, -1)  # keep last 20 entries
        pipe.expire(redis_key, settings.redis_session_ttl_seconds)
        await pipe.execute()

    transcript_window = await redis.lrange(redis_key, 0, -1)
    
    # Generate response based on the updated prompt logic
    ai_response = await generate_emotional_response(transcript_window)

    return {
        "session_id": session_id,
        "transcript": transcript,
        "response": ai_response,
    }

# @app.post("/session")
# async def create_session():
#     session_id = str(uuid.uuid4())
#     # Initialize the session key with an expiry
#     await redis.setex(
#         f"session:{session_id}", 
#         settings.redis_session_ttl_seconds, 
#         "session_start"
#     )
#     return {"session_id": session_id}

@app.post("/session")
async def create_session():
    session_id = str(uuid.uuid4())
    # Don't set the key here! Let process_audio create the list.
    return {"session_id": session_id}