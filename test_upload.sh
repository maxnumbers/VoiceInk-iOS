#!/bin/bash

# Test script for VoiceInk HTTP Server
# Replace IPHONE_IP with your iPhone's actual IP address

IPHONE_IP="192.168.1.XXX"  # CHANGE THIS
PORT=8080

echo "Testing VoiceInk HTTP Server at $IPHONE_IP:$PORT"
echo ""

# Test 1: Health check
echo "1. Testing health endpoint..."
curl -s http://$IPHONE_IP:$PORT/health
echo ""
echo ""

# Test 2: Server status
echo "2. Testing root endpoint..."
curl -s http://$IPHONE_IP:$PORT/
echo ""
echo ""

# Test 3: Upload audio (requires test file)
if [ -f "test_audio.wav" ]; then
    echo "3. Testing audio upload..."
    curl -X POST http://$IPHONE_IP:$PORT/api/upload/audio \
      -H "Content-Type: audio/wav" \
      --data-binary @test_audio.wav
    echo ""
else
    echo "3. Skipping audio upload test (no test_audio.wav found)"
    echo "   To test upload, create a WAV file and run:"
    echo "   curl -X POST http://$IPHONE_IP:$PORT/api/upload/audio -H \"Content-Type: audio/wav\" --data-binary @test_audio.wav"
fi

echo ""
echo "Done!"
