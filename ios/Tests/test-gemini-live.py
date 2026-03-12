#!/usr/bin/env python3
"""Gemini Live integration test — multi-turn check-in with function calling."""
import asyncio, json, os, sys

try:
    import websockets
except ModuleNotFoundError:
    websockets = None

API_KEY = os.environ.get("GEMINI_API_KEY", "")
MODEL = "gemini-2.5-flash-native-audio-preview-12-2025"
WS_URL = f"wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key={API_KEY}"

CHECK_IN_TOOLS = [
    {
        "name": "get_check_in_guidance",
        "description": "Get guidance for the current health check-in conversation. Call this BEFORE responding to the member to get context about which topics have been covered, what to ask next, their emotional state, and their active medications. Always call this during a check-in.",
        "parameters": {"type": "OBJECT", "properties": {}}
    },
    {
        "name": "complete_check_in",
        "description": "Complete the health check-in. Call this when all topics have been naturally covered and it's time to wrap up. This saves the check-in data and syncs it to the health knowledge graph.",
        "parameters": {"type": "OBJECT", "properties": {}}
    }
]

SYSTEM_PROMPT = """You are Mira, a warm wellness companion helping with a daily check-in.

RULES (follow strictly):
1. ALWAYS call get_check_in_guidance BEFORE every response to the user.
2. Read the guidance carefully. Use topicsRemaining and instruction to decide what to ask.
3. When recommendedAction is "close", say a brief warm goodbye and then call complete_check_in.
4. Keep responses to 1-2 short sentences.
5. Be warm but concise."""

def guidance_for_turn(turn):
    topics_progression = [
        ([], ["mood", "sleep", "symptoms", "medication"], "ask", "mood",
         "Greet them warmly and ask about their mood today."),
        (["mood"], ["sleep", "symptoms", "medication"], "affirm", "sleep",
         "Affirm their positive mood, then ask about sleep."),
        (["mood", "sleep"], ["symptoms", "medication"], "ask", "symptoms",
         "Good sleep reported. Ask about any symptoms today."),
        (["mood", "sleep", "symptoms"], ["medication"], "affirm", "medication",
         "Mild symptoms — affirm. Ask about medication adherence."),
        (["mood", "sleep", "symptoms", "medication"], [], "close", "",
         "All topics covered. Wrap up warmly and call complete_check_in."),
    ]
    idx = min(turn, len(topics_progression) - 1)
    covered, remaining, action, hint, instruction = topics_progression[idx]
    return {
        "topicsCovered": covered,
        "topicsRemaining": remaining,
        "activeMedications": ["Levodopa 100mg 3x/day"],
        "emotion": "calm",
        "engagementLevel": "medium",
        "recommendedAction": action,
        "nextTopicHint": hint,
        "instruction": instruction
    }

# ── Test 1: Basic text round-trip ──────────────────────────────────

async def test_basic_roundtrip():
    print("\n=== Test 1: Basic text→audio round-trip ===")
    async with websockets.connect(WS_URL) as ws:
        await ws.send(json.dumps({"setup": {
            "model": f"models/{MODEL}",
            "generationConfig": {
                "responseModalities": ["AUDIO"],
                "temperature": 0.7,
                "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": "Puck"}}}
            },
            "systemInstruction": {"parts": [{"text": "Keep responses to one sentence."}]},
            "outputAudioTranscription": {},
        }}))
        while True:
            msg = json.loads(await ws.recv())
            if "setupComplete" in msg: break

        await ws.send(json.dumps({"clientContent": {
            "turns": [{"role": "user", "parts": [{"text": "Say exactly: PONG"}]}],
            "turnComplete": True
        }}))

        transcript = ""
        while True:
            msg = json.loads(await ws.recv())
            sc = msg.get("serverContent", {})
            ot = sc.get("outputTranscription", {})
            if "text" in ot: transcript += ot["text"]
            if sc.get("turnComplete"): break

        ok = bool(transcript.strip())
        print(f"  Transcript: \"{transcript}\"")
        print(f"  {'PASS' if ok else 'FAIL'}")
        return ok

# ── Test 2: Function call triggers ─────────────────────────────────

async def test_function_call_triggers():
    print("\n=== Test 2: get_check_in_guidance called before response ===")
    async with websockets.connect(WS_URL) as ws:
        await ws.send(json.dumps({"setup": {
            "model": f"models/{MODEL}",
            "generationConfig": {
                "responseModalities": ["AUDIO"],
                "temperature": 0.7,
                "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": "Puck"}}}
            },
            "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]},
            "tools": [{"functionDeclarations": CHECK_IN_TOOLS}],
            "outputAudioTranscription": {},
        }}))
        while True:
            msg = json.loads(await ws.recv())
            if "setupComplete" in msg: break

        await ws.send(json.dumps({"clientContent": {
            "turns": [{"role": "user", "parts": [{"text": "Hi Mira, I'm ready for my check-in"}]}],
            "turnComplete": True
        }}))

        # Wait for first tool call
        tool_name = None
        tool_id = None
        while True:
            msg = json.loads(await ws.recv())
            tc = msg.get("toolCall", {})
            fcs = tc.get("functionCalls", [])
            if fcs:
                tool_name = fcs[0]["name"]
                tool_id = fcs[0]["id"]
                break
            if msg.get("serverContent", {}).get("turnComplete"):
                print("  FAIL — turn completed without tool call")
                return False

        ok = tool_name == "get_check_in_guidance"
        print(f"  First tool call: {tool_name} (id={tool_id})")
        print(f"  {'PASS' if ok else 'FAIL — expected get_check_in_guidance'}")

        # Send guidance response and verify model speaks
        if ok:
            await ws.send(json.dumps({"toolResponse": {
                "functionResponses": [{"id": tool_id, "response": guidance_for_turn(0)}]
            }}))
            transcript = ""
            while True:
                msg = json.loads(await ws.recv())
                sc = msg.get("serverContent", {})
                ot = sc.get("outputTranscription", {})
                if "text" in ot: transcript += ot["text"]
                if sc.get("turnComplete"): break
            print(f"  Model response: \"{transcript[:120]}\"")
            ok = ok and bool(transcript.strip())

        return ok

# ── Test 3: Full multi-turn check-in ──────────────────────────────

async def test_full_checkin():
    print("\n=== Test 3: Full multi-turn check-in conversation ===")
    async with websockets.connect(WS_URL) as ws:
        await ws.send(json.dumps({"setup": {
            "model": f"models/{MODEL}",
            "generationConfig": {
                "responseModalities": ["AUDIO"],
                "temperature": 0.7,
                "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": "Puck"}}}
            },
            "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]},
            "tools": [{"functionDeclarations": CHECK_IN_TOOLS}],
            "outputAudioTranscription": {},
        }}))
        while True:
            msg = json.loads(await ws.recv())
            if "setupComplete" in msg: break

        user_msgs = [
            "Hi Mira, I'm ready for my check-in",
            "I'm feeling pretty good today, calm and positive",
            "I slept about 7 hours, woke up once but went back to sleep easily",
            "My tremor was really mild today, no stiffness at all",
            "Yes I took my Levodopa this morning on schedule",
            "Thanks Mira, have a great day!",
        ]

        guidance_calls = 0
        complete_calls = 0
        responses = []
        check_in_done = False

        for turn, user_msg in enumerate(user_msgs):
            if check_in_done:
                break

            print(f"\n  [Turn {turn}] User: {user_msg}")
            await ws.send(json.dumps({"clientContent": {
                "turns": [{"role": "user", "parts": [{"text": user_msg}]}],
                "turnComplete": True
            }}))

            # Process events until turnComplete
            transcript = ""
            while True:
                msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=45))

                # Tool call
                tc = msg.get("toolCall", {})
                fcs = tc.get("functionCalls", [])
                for fc in fcs:
                    name = fc["name"]
                    fid = fc["id"]
                    print(f"  [Turn {turn}] Tool: {name}")

                    if name == "get_check_in_guidance":
                        guidance_calls += 1
                        await ws.send(json.dumps({"toolResponse": {
                            "functionResponses": [{"id": fid, "response": guidance_for_turn(turn)}]
                        }}))
                    elif name == "complete_check_in":
                        complete_calls += 1
                        await ws.send(json.dumps({"toolResponse": {
                            "functionResponses": [{"id": fid, "response": {"success": True, "durationSeconds": 60}}]
                        }}))
                        check_in_done = True

                # Transcription
                sc = msg.get("serverContent", {})
                ot = sc.get("outputTranscription", {})
                if "text" in ot:
                    transcript += ot["text"]

                if sc.get("turnComplete"):
                    break

            if transcript.strip():
                responses.append(transcript)
                print(f"  [Turn {turn}] Mira: {transcript[:150]}")

        # Summary
        print(f"\n  ========= CHECK-IN SUMMARY =========")
        print(f"  Guidance calls: {guidance_calls}")
        print(f"  Complete calls: {complete_calls}")
        print(f"  Model responses: {len(responses)}")
        print(f"  Check-in completed: {check_in_done}")
        print(f"  ======================================")

        # Assertions
        results = []
        def check(cond, msg):
            results.append(cond)
            print(f"  {'PASS' if cond else 'FAIL'}: {msg}")

        check(guidance_calls >= 3, f"get_check_in_guidance called >= 3 times (got {guidance_calls})")
        check(complete_calls == 1, f"complete_check_in called exactly once (got {complete_calls})")
        check(check_in_done, "Check-in completed successfully")
        check(len(responses) >= 3, f"At least 3 model responses (got {len(responses)})")

        return all(results)

# ── Main ───────────────────────────────────────────────────────────

async def main():
    if not API_KEY:
        print("ERROR: GEMINI_API_KEY is required to run this script.")
        print("       Example: GEMINI_API_KEY=your_key python3 Tests/test-gemini-live.py")
        sys.exit(1)

    if websockets is None:
        print("ERROR: Missing Python dependency: websockets")
        print("       Install it with: python3 -m pip install websockets")
        sys.exit(1)

    print("=" * 50)
    print("Gemini Live Integration Tests")
    print(f"Model: {MODEL}")
    print(f"Mode: text input (clientContent) → audio output + transcription")
    print("=" * 50)

    results = []
    results.append(await test_basic_roundtrip())
    results.append(await test_function_call_triggers())
    results.append(await test_full_checkin())

    passed = sum(results)
    total = len(results)
    print(f"\n{'=' * 50}")
    print(f"Results: {passed}/{total} passed")
    print(f"{'=' * 50}")

    if passed < total:
        exit(1)

asyncio.run(main())
