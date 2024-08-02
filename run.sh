#!/bin/sh
echo "INFO     Chat With Eliza - $VERSION"
fastapi run lambda.py --proxy-headers --port 8080