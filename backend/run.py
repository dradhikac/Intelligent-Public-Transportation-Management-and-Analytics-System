"""
TransitIQ Backend Runner
Usage:
    python backend/run.py
"""

import uvicorn
import os
import sys

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    host = os.environ.get("HOST", "127.0.0.1")
    print(f"==================================================")
    print(f"TRANSITIQLAB: LAUNCHING BACKEND API SERVER")
    print(f"API Server    : http://{host}:{port}")
    print(f"Documentation : http://{host}:{port}/docs")
    print(f"Dashboard     : http://{host}:{port}/")
    print(f"==================================================")
    uvicorn.run("backend.main:app", host=host, port=port, reload=True)
