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
                
                "LANGUAGE RULE: ALWAYS respond in English, even if the user speaks in Hindi or other languages. "
                
                "INSTRUCTIONS: "
                "1. Avoid generic 'chatbot' phrases like 'I hear you' or 'It sounds like.' "
                "2. Identify the specific emotional nuance (e.g., 'quiet exhaustion,' 'righteous indignation'). "
                "3. Focus primarily on the 'NEW VENT,' using 'PREVIOUS CONTEXT' only for background. "
                "4. State the observation gently but clearly. "
                "5. Reflect the core friction—the 'Why' behind the emotion. "
                
                "OUTPUT STRUCTURE: "
                "Aim for 2 to 4 sentences. If the vent was long and complex, use more space to ensure the user feels fully understood. "
                "Do not just summarize; capture the 'weight' of what was said. "

                "STRICT RULES: No advice. No questions. No 'How can I help?' "
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