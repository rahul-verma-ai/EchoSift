from openai import AsyncOpenAI
from ..core.config import get_settings


settings = get_settings()
client = AsyncOpenAI(api_key=settings.openai_api_key)


async def transcribe_audio(audio_bytes: bytes, filename: str) -> str:
    """
    Uses OpenAI Whisper via the official SDK.
    Audio is passed in-memory only.
    """
    response = await client.audio.transcriptions.create(
        file=(filename, audio_bytes),
        model="whisper-1"
    )
    return response.text


async def generate_emotional_response(transcript_window: list[str]) -> str:
    """
    Uses GPT-4o-mini for emotional mirroring.
    Transcript window is a rolling context (Redis-managed).
    """
    messages = [
    {
        "role": "system",
        "content": (
            "ROLE: COMPASSIONATE EMOTIONAL MIRROR. "
            "GOAL: Distill raw venting into a precise, validating reflection. "
            
            "LANGUAGE RULE: ALWAYS respond in English, even if the user speaks in Hindi or other languages. "
            
            "INSTRUCTIONS: "
            "1. Avoid generic 'chatbot' phrases like 'I hear you' or 'It sounds like.' "
            "2. Identify the specific emotional nuance (e.g., 'quiet exhaustion,' 'righteous indignation'). "
            "3. State the observation gently but clearly. "
            "4. Reflect the core friction—the 'Why' behind the emotion. "
            
            "OUTPUT STRUCTURE: "
            "Aim for 2 to 4 sentences. If the vent was long and complex, use more space to ensure the user feels fully understood. "
            "Do not just summarize; capture the 'weight' of what was said. "

            "STRICT RULES: No advice. No questions. No 'How can I help?' "
            "TONE: Calming, precise, and human. "
        ),
    },
    {
        "role": "user",
        "content": f"User Input: {' '.join(transcript_window)}",
    },
    ]

    response = await client.chat.completions.create(
        model="gpt-4o-mini",
        messages=messages,
        temperature=0.7,
        max_tokens=250, # Ensures it has enough room to talk if needed
    )
    return response.choices[0].message.content