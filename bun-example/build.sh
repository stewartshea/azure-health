#!/bin/bash

# Build script for Bun executable
echo "Building Bun executable..."

bun build index.js --compile --outfile bun-example

if [ $? -eq 0 ]; then
    echo "✅ Build successful! Executable created: bun-example"
    echo "You can now copy 'bun-example' to any remote system and run it."
    chmod +x bun-example
else
    echo "❌ Build failed"
    exit 1
fi

