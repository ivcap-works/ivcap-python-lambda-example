from fastapi import FastAPI
from eliza import eliza
from signal import signal, SIGTERM
import sys
import os

# shutdown pod cracefully
signal(SIGTERM, lambda _1, _2: sys.exit(0))

description = """
Chat with Eliza Service. 🚀

ELIZA is a natural language processing program developed from 1964 to 1966
by Joseph Weizenbaum, originally implemented in MAD-SLIP.
You can find the 1966 paper at https://dl.acm.org/doi/10.1145/365153.365168.

ELIZA uses pattern matching, decomposition and reassembly rules to emulate
a Rogerian psychotherapist.
"""

app = FastAPI(
    title="Chat With Eliza",
    description=description,
    summary="Implementation of Joseph Weizenbaum's famous Eliza chat-bot.",
    version=os.environ.get("VERSION", "???"),
    contact={
        "name": "Max Ott",
        "email": "max.ott@data61.csiro.au",
    },
    license_info={
        "name": "MIT",
        "url": "https://opensource.org/license/MIT",
    },
    docs_url="/", # ONLY set when there is no default GET
    root_path=os.environ.get("IVCAP_ROOT_PATH", "")
)

eliza = eliza.Eliza()
eliza.load('eliza/doctor.txt')

@app.post("/")
def root(said: str):
    response = eliza.respond(said)
    return {
        "input": said,
        "response": response
    }

# Allows platform to check if everything is OK
@app.get("/_healtz")
def healtz():
    return {"version": os.environ.get("VERSION", "???")}
