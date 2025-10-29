#!/bin/bash

# Create a test WAV file using ffmpeg or sox
# This creates a 3-second tone at 16kHz mono (VoiceInk's preferred format)

if command -v ffmpeg &> /dev/null; then
    echo "Creating test audio with ffmpeg..."
    ffmpeg -f lavfi -i "sine=frequency=440:duration=3" -ar 16000 -ac 1 -y test_audio.wav
    echo "Created test_audio.wav (440Hz tone, 3 seconds, 16kHz mono)"
elif command -v sox &> /dev/null; then
    echo "Creating test audio with sox..."
    sox -n -r 16000 -c 1 test_audio.wav synth 3 sine 440
    echo "Created test_audio.wav (440Hz tone, 3 seconds, 16kHz mono)"
else
    echo "Neither ffmpeg nor sox found."
    echo "Please install one of them or use an existing WAV file."
    echo ""
    echo "macOS: brew install ffmpeg"
    echo "       or: brew install sox"
fi
