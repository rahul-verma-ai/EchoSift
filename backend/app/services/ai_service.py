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
    Separates history from the current vent to prevent 'stuck' analysis.
    """
    
    # 1. Prepare the context
    # If there's only one item, history is empty. 
    # Otherwise, everything except the last item is history.
    if len(transcript_window) > 1:
        history_text = "\n".join(transcript_window[:-1])
        current_vent = transcript_window[-1]
        user_content = (
            f"PREVIOUS CONTEXT:\n{history_text}\n\n"
            f"NEW VENT TO ANALYZE NOW:\n{current_vent}"
        )
    else:
        current_vent = transcript_window[0]
        user_content = f"NEW VENT TO ANALYZE NOW:\n{current_vent}"

    messages = [
        {
            "role": "system",
            "content": (
                "ROLE: COMPASSIONATE EMOTIONAL MIRROR. "
                "GOAL: Distill raw venting into a precise, validating reflection. "

                "LANGUAGE RULE: ALWAYS respond in English. "

                "STRICT BREVITY RULE: "
                "If the 'NEW VENT' is short (1 sentence), respond with exactly ONE profound sentence. "
                "If the vent is long, use 2-3 sentences max. Never exceed 60 words. "

                "INSTRUCTIONS: "
                "1. No 'chatbot' filler (e.g., 'I hear you', 'It seems'). "
                "2. Name the specific nuance (e.g., 'lingering resentment', 'fading hope'). "
                "3. Focus on the 'NEW VENT'; use 'PREVIOUS CONTEXT' only to detect patterns. "
                "4. No advice. No questions. No 'How can I help?' "

                "TONE: Calming, precise, and human. "
            ),
        },
        {
            "role": "user",
            "content": user_content,
        },
    ]

    response = await client.chat.completions.create(
        model="gpt-4o-mini",
        messages=messages,
        temperature=0.7,
        max_tokens=250,
    )
    
    return response.choices[0].message.content